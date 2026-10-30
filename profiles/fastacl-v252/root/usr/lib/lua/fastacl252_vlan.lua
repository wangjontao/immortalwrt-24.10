local M={}
local policy=require 'fastacl252'

local BASE_PREFIX='192.168'
local OWNER='fastacl252-vlan'
local RULE_SUFFIX={'dhcp','dns','tproxy'}

local function fail(message) error(message,0) end
local function integer(value,low,high,message)
  local number=tonumber(value)
  if not number or number~=math.floor(number) or number<low or number>high then
    fail(message)
  end
  return number
end
local function trim(value)
  return tostring(value or ''):gsub('^%s+',''):gsub('%s+$','')
end
local function short_text(value,limit,message)
  value=trim(value)
  if value=='' or #value>limit or value:find('[%z\1-\31\127]') then fail(message) end
  return value
end
local function enabled(u)
  return u:get('fastacl252','main','vlan_mode')=='1'
end
local function configured_trunk(u)
  local value=tostring(u:get('fastacl252','main','vlan_trunk') or '')
  if policy.dev(value) then return value end
  return ''
end
local function physical_interfaces()
  local sys=require 'luci.sys'
  local out=sys.exec("ls -1 /sys/class/net 2>/dev/null") or ''
  local rows={}
  for name in out:gmatch('[^\n]+') do
    if policy.dev(name) and not name:match('^lo$') and
       not name:match('^br%-') and not name:match('^bond') and
       not name:match('^vlan') and not name:match('^virbr') and
       not name:match('^docker') and not name:match('^veth') then
      rows[#rows+1]=name
    end
  end
  table.sort(rows)
  return rows
end
local function wan_interfaces(u)
  local blocked={}
  local wan=u:get('network','wan','device') or u:get('network','wan','ifname')
  if type(wan)=='table' then
    for _,value in ipairs(wan) do blocked[tostring(value)]=true end
  elseif wan and wan~='' then blocked[tostring(wan)]=true end
  local sys=require 'luci.sys'
  local route=sys.exec("ip -4 route show default 2>/dev/null | awk '$1 == \"default\" {print $5; exit}'") or ''
  route=route:gsub('%s+','')
  if route~='' then blocked[route]=true end
  return blocked
end
local function bridge_ports(u,name)
  local ports={}
  u:foreach('network','device',function(device)
    if device.name==name then
      local values=device.ports
      if type(values)~='table' then values={values} end
      for _,port in ipairs(values) do
        port=tostring(port or ''):gsub(':.*$','')
        if policy.dev(port) then ports[#ports+1]=port end
      end
    end
  end)
  return ports
end
local function detected_trunk(u)
  local lan_device=tostring(u:get('network','lan','device') or u:get('network','lan','ifname') or '')
  local candidates={}
  if policy.dev(lan_device) and not lan_device:match('^br%-') then
    candidates[#candidates+1]=lan_device
  elseif lan_device~='' then
    for _,port in ipairs(bridge_ports(u,lan_device)) do candidates[#candidates+1]=port end
  end
  if #candidates==0 then
    local blocked=wan_interfaces(u)
    for _,name in ipairs(physical_interfaces()) do
      if not blocked[name] then candidates[#candidates+1]=name end
    end
  end
  return candidates[1] or '',candidates
end
local function trunk(u,requested)
  local value=trim(requested)
  if value=='' then value=configured_trunk(u) end
  if value=='' then value=detected_trunk(u) end
  if not policy.dev(value) then fail('请选择有效的 LAN Trunk 网口') end
  local _,candidates=detected_trunk(u)
  local found=false
  for _,candidate in ipairs(candidates) do if candidate==value then found=true end end
  if not found and configured_trunk(u)==value then found=true end
  if not found then fail('Trunk 网口不存在或已被 WAN 使用: '..value) end
  return value,candidates
end
local function cidr_range(value)
  local ip,prefix=tostring(value or ''):match('^([^/]+)/(%d+)$')
  local start=policy.ipnum(ip)
  prefix=tonumber(prefix)
  if not start or not prefix or prefix<1 or prefix>32 then return nil end
  local size=2^(32-prefix)
  local first=math.floor(start/size)*size
  return first,first+size-1
end
local function overlaps(a,b)
  local a1,a2=cidr_range(a)
  local b1,b2=cidr_range(b)
  if not a1 or not b1 then return true end
  return not (a2<b1 or a1>b2)
end
local function existing_subnets(u)
  local rows={}
  u:foreach('network','interface',function(section)
    local addresses=type(section.ipaddr)=='table' and section.ipaddr or {section.ipaddr}
    for _,address in ipairs(addresses) do
      if address and address~='' then
        local prefix=policy.prefix(section.netmask or '32')
        if prefix then
          rows[#rows+1]={network=section['.name'],cidr=policy.cidr(address,prefix)}
        end
      end
    end
  end)
  local sys=require 'luci.sys'
  local routes=sys.exec('ip -4 route show 2>/dev/null') or ''
  for line in routes:gmatch('[^\n]+') do
    local destination=line:match('^(%d+%.%d+%.%d+%.%d+/?%d*)%s')
    if destination then
      if not destination:find('/') then destination=destination..'/32' end
      rows[#rows+1]={network='route',cidr=destination}
    end
  end
  return rows
end
local function validate_node(u,node,preproxy)
  node=trim(node)
  preproxy=trim(preproxy)
  if node=='' then return 'direct','','' end
  if u:get('fastacl252',node)~='node' then fail('请选择有效代理节点') end
  if preproxy~='' then
    if preproxy==node or u:get('fastacl252',preproxy)~='node' then fail('请选择有效前置节点') end
  end
  return 'proxy',node,preproxy
end
local function set_dns(u,section,request,mode)
  local dns=require 'fastacl252_dns'
  local id=tostring(request.dns or 'inherit')
  if not dns.valid_id(id) then fail('DNS 选择无效') end
  if id~='inherit' and id~='custom' then
    if not dns.provider(id) then fail('DNS 服务商不存在') end
    if not dns.allowed(id,mode) then
      if mode=='proxy' then id='inherit' else fail('当前出口不支持此 DNS') end
    end
  end
  local temporary={dns=id,dns_type=request.dns_type,dns_ip=request.dns_ip,dns_name=request.dns_name}
  local main=u:get_all('fastacl252','main') or {}
  dns.resolve(temporary,mode,main,{},'vlan')
  u:set('fastacl252',section,'dns',id)
  if id=='custom' then
    u:set('fastacl252',section,'dns_type',temporary.dns_type or 'doh')
    u:set('fastacl252',section,'dns_ip',temporary.dns_ip or '')
    u:set('fastacl252',section,'dns_name',temporary.dns_name or '')
  else
    u:delete('fastacl252',section,'dns_type')
    u:delete('fastacl252',section,'dns_ip')
    u:delete('fastacl252',section,'dns_name')
  end
end
local function add(u,config,kind,name,values)
  if u:get(config,name) then fail('配置名称冲突: '..config..'.'..name) end
  if not policy.section(u,config,kind,name,values) then fail('创建配置失败: '..config..'.'..name) end
end
local function section_ids(u)
  local ids={}
  u:foreach('fastacl252','vlan',function(section) ids[section['.name']]=true end)
  return ids
end
local function plan(u,request)
  request=request or {}
  if not enabled(u) then fail('当前设备未启用 X86 VLAN 模式') end
  local count=integer(request.count or 1,1,32,'一次最多创建 32 个 VLAN')
  local start_vlan=integer(request.start_vlan or 10,2,4094,'VLAN ID 必须在 2–4094')
  local start_subnet=integer(request.start_subnet or math.min(start_vlan,254),1,254,'起始网段必须在 1–254')
  if start_vlan+count-1>4094 then fail('VLAN ID 超出范围') end
  if start_subnet+count-1>254 then fail('网段超出 192.168.1.0/24–192.168.254.0/24') end
  local ssid_prefix=short_text(request.ssid_prefix or 'JuLiang',24,'SSID 前缀无效')
  local name_prefix=short_text(request.name_prefix or 'VLAN',32,'VLAN 名称前缀无效')
  local selected_trunk,candidates=trunk(u,request.trunk)
  local ids=section_ids(u)
  local subnets=existing_subnets(u)
  local rows={}
  for index=0,count-1 do
    local vlan=start_vlan+index
    local subnet_index=start_subnet+index
    local id='jfa25v'..vlan
    if u:get('network',id) or u:get('dhcp',id) or u:get('firewall',id) or ids[id] then
      fail('VLAN 配置已存在: '..vlan)
    end
    local subnet=string.format('%s.%d.0/24',BASE_PREFIX,subnet_index)
    for _,row in ipairs(subnets) do
      if overlaps(subnet,row.cidr) then fail('网段冲突: '..subnet..' 与 '..row.network..' '..row.cidr) end
    end
    local ssid=ssid_prefix..'-'..vlan
    if #ssid>32 then fail('SSID 超过 32 字节: '..ssid) end
    rows[#rows+1]={
      id=id,
      vlan=vlan,
      name=string.format('%s %d',name_prefix,vlan),
      ssid=ssid,
      trunk=selected_trunk,
      interface=selected_trunk..'.'..vlan,
      network=id,
      subnet=subnet,
      router=string.format('%s.%d.1',BASE_PREFIX,subnet_index)
    }
    subnets[#subnets+1]={network=id,cidr=subnet}
  end
  return rows,selected_trunk,candidates
end

function M.candidates(u)
  local selected,candidates=detected_trunk(u)
  return selected,candidates
end

function M.plan(u,request)
  local rows,selected_trunk,candidates=plan(u,request)
  return {enabled=enabled(u),trunk=selected_trunk,candidates=candidates,rows=rows}
end

function M.status(u)
  local rows={}
  u:foreach('fastacl252','vlan',function(section)
    rows[#rows+1]={
      id=section['.name'],
      vlan=tonumber(section.vlan),
      name=section.name or section['.name'],
      ssid=section.ssid or '',
      trunk=section.trunk or configured_trunk(u),
      interface=section.interface or '',
      network=section.network or '',
      subnet=section.subnet or '',
      router=section.router or '',
      mode=section.mode or 'direct',
      node=section.node or '',
      preproxy=section.preproxy or '',
      dns=section.dns or 'inherit'
    }
  end)
  table.sort(rows,function(a,b) return (a.vlan or 0)<(b.vlan or 0) end)
  local selected,candidates=detected_trunk(u)
  return {enabled=enabled(u),trunk=configured_trunk(u)~='' and configured_trunk(u) or selected,candidates=candidates,rows=rows}
end

function M.create_batch(u,request)
  local rows,selected_trunk=plan(u,request)
  local mode,node,preproxy=validate_node(u,request.node,request.preproxy)
  local dhcp_start=integer(request.dhcp_start or 100,2,250,'DHCP 起始地址无效')
  local dhcp_limit=integer(request.dhcp_limit or 120,1,252,'DHCP 地址数量无效')
  if dhcp_start+dhcp_limit-1>254 then fail('DHCP 地址范围超出网段') end
  for _,row in ipairs(rows) do
    add(u,'network','device',row.id..'_dev',{
      name=row.interface,
      type='8021q',
      ifname=selected_trunk,
      vid=tostring(row.vlan)
    })
    add(u,'network','interface',row.id,{
      device=row.interface,
      proto='static',
      ipaddr=row.router,
      netmask='255.255.255.0',
      delegate='0'
    })
    add(u,'dhcp','dhcp',row.id,{
      interface=row.id,
      start=tostring(dhcp_start),
      limit=tostring(dhcp_limit),
      leasetime='12h',
      dhcpv6='disabled',
      ra='disabled',
      ndp='disabled',
      dhcp_option={'3,'..row.router,'6,'..row.router}
    })
    add(u,'firewall','zone',row.id,{
      name=row.id,
      network={row.id},
      input='REJECT',
      output='ACCEPT',
      forward='REJECT',
      masq='1'
    })
    add(u,'firewall','rule',row.id..'_dhcp',{
      name='FastACL '..row.id..' DHCP',
      src=row.id,
      proto='udp',
      dest_port='67',
      family='ipv4',
      target='ACCEPT'
    })
    add(u,'firewall','rule',row.id..'_dns',{
      name='FastACL '..row.id..' DNS',
      src=row.id,
      proto='tcp udp',
      dest_port='53 12553',
      family='ipv4',
      target='ACCEPT'
    })
    add(u,'firewall','rule',row.id..'_tproxy',{
      name='FastACL '..row.id..' TPROXY',
      src=row.id,
      proto='tcp udp',
      mark='0x2028',
      family='ipv4',
      target='ACCEPT'
    })
    add(u,'firewall','forwarding',row.id..'_wan',{src=row.id,dest='wan'})
    add(u,'fastacl252','vlan',row.id,{
      owner=OWNER,
      vlan=tostring(row.vlan),
      name=row.name,
      ssid=row.ssid,
      trunk=selected_trunk,
      interface=row.interface,
      network=row.id,
      subnet=row.subnet,
      router=row.router,
      mode=mode,
      node=node,
      preproxy=preproxy
    })
    set_dns(u,row.id,request,mode)
  end
  u:set('fastacl252','main','vlan_mode','1')
  u:set('fastacl252','main','vlan_trunk',selected_trunk)
  return rows
end

function M.update(u,request)
  local id=trim(request.id)
  local section=u:get_all('fastacl252',id)
  if not section or section['.type']~='vlan' or section.owner~=OWNER then fail('VLAN 策略不存在') end
  local mode,node,preproxy=validate_node(u,request.node,request.preproxy)
  u:set('fastacl252',id,'mode',mode)
  u:set('fastacl252',id,'node',node)
  u:set('fastacl252',id,'preproxy',preproxy)
  set_dns(u,id,request,mode)
  return {id=id,mode=mode,node=node,preproxy=preproxy}
end

function M.remove_many(u,ids)
  if type(ids)~='table' or #ids==0 or #ids>32 then fail('请选择 1–32 个 VLAN') end
  local selected={}
  for _,id in ipairs(ids) do
    id=trim(id)
    local section=u:get_all('fastacl252',id)
    if not section or section['.type']~='vlan' or section.owner~=OWNER then fail('VLAN 策略不存在: '..id) end
    if selected[id] then fail('VLAN 重复: '..id) end
    selected[id]=true
  end
  local removed={}
  for id in pairs(selected) do
    u:delete('network',id..'_dev')
    u:delete('network',id)
    u:delete('dhcp',id)
    u:delete('firewall',id)
    for _,suffix in ipairs(RULE_SUFFIX) do u:delete('firewall',id..'_'..suffix) end
    u:delete('firewall',id..'_wan')
    u:delete('fastacl252',id)
    removed[#removed+1]=id
  end
  table.sort(removed)
  return removed
end

return M
