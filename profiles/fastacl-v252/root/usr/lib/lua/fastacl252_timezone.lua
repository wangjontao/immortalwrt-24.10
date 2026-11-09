-- POSIX timezone rules avoid requiring the large zoneinfo package.
local M={}
local zones={
 ['Asia/Shanghai']={posix='CST-8',label='中国标准时间'},
 ['Asia/Hong_Kong']={posix='HKT-8',label='香港时间'},
 ['Asia/Taipei']={posix='CST-8',label='台北时间'},
 ['Asia/Tokyo']={posix='JST-9',label='日本时间'},
 ['Asia/Seoul']={posix='KST-9',label='韩国时间'},
 ['Asia/Singapore']={posix='<+08>-8',label='新加坡时间'},
 ['Asia/Bangkok']={posix='<+07>-7',label='泰国时间'},
 ['Asia/Kolkata']={posix='IST-5:30',label='印度时间'},
 ['Asia/Dubai']={posix='<+04>-4',label='阿联酋时间'},
 ['Europe/London']={posix='GMT0BST,M3.5.0/1,M10.5.0',label='英国时间'},
 ['Europe/Berlin']={posix='CET-1CEST,M3.5.0,M10.5.0/3',label='中欧时间'},
 ['Europe/Paris']={posix='CET-1CEST,M3.5.0,M10.5.0/3',label='中欧时间'},
 ['Europe/Madrid']={posix='CET-1CEST,M3.5.0,M10.5.0/3',label='中欧时间'},
 ['Europe/Rome']={posix='CET-1CEST,M3.5.0,M10.5.0/3',label='中欧时间'},
 ['Europe/Amsterdam']={posix='CET-1CEST,M3.5.0,M10.5.0/3',label='中欧时间'},
 ['Europe/Moscow']={posix='MSK-3',label='莫斯科时间'},
 ['America/New_York']={posix='EST5EDT,M3.2.0,M11.1.0',label='美国东部时间'},
 ['America/Chicago']={posix='CST6CDT,M3.2.0,M11.1.0',label='美国中部时间'},
 ['America/Denver']={posix='MST7MDT,M3.2.0,M11.1.0',label='美国山地时间'},
 ['America/Phoenix']={posix='MST7',label='美国亚利桑那时间'},
 ['America/Los_Angeles']={posix='PST8PDT,M3.2.0,M11.1.0',label='美国太平洋时间'},
 ['America/Anchorage']={posix='AKST9AKDT,M3.2.0,M11.1.0',label='阿拉斯加时间'},
 ['Pacific/Honolulu']={posix='HST10',label='夏威夷时间'},
 ['America/Toronto']={posix='EST5EDT,M3.2.0,M11.1.0',label='加拿大东部时间'},
 ['America/Vancouver']={posix='PST8PDT,M3.2.0,M11.1.0',label='加拿大西部时间'},
 ['America/Sao_Paulo']={posix='<-03>3',label='巴西时间'},
 ['Australia/Sydney']={posix='AEST-10AEDT,M10.1.0,M4.1.0/3',label='澳洲东部时间'},
 ['Australia/Melbourne']={posix='AEST-10AEDT,M10.1.0,M4.1.0/3',label='澳洲东南部时间'},
 ['Australia/Brisbane']={posix='AEST-10',label='澳洲昆士兰时间'},
 ['Australia/Perth']={posix='AWST-8',label='澳洲西部时间'},
 ['Pacific/Auckland']={posix='NZST-12NZDT,M9.5.0,M4.1.0/3',label='新西兰时间'}
}
local countries={
 CN='Asia/Shanghai',HK='Asia/Hong_Kong',TW='Asia/Taipei',JP='Asia/Tokyo',KR='Asia/Seoul',SG='Asia/Singapore',TH='Asia/Bangkok',IN='Asia/Kolkata',AE='Asia/Dubai',
 GB='Europe/London',UK='Europe/London',DE='Europe/Berlin',FR='Europe/Paris',ES='Europe/Madrid',IT='Europe/Rome',NL='Europe/Amsterdam',RU='Europe/Moscow',
 US='America/New_York',CA='America/Toronto',BR='America/Sao_Paulo',AU='Australia/Sydney',NZ='Pacific/Auckland'
}
local rules={
 {'America/New_York','纽约','new york','波士顿','boston','华盛顿','washington','迈阿密','miami','亚特兰大','atlanta'},
 {'America/Chicago','芝加哥','chicago','达拉斯','dallas','休斯顿','houston'},
 {'America/Denver','丹佛','denver','盐湖城','salt lake'},
 {'America/Phoenix','凤凰城','phoenix','亚利桑那','arizona'},
 {'America/Los_Angeles','洛杉矶','los angeles','旧金山','san francisco','硅谷','圣何塞','san jose','西雅图','seattle','拉斯维加斯','las vegas','圣迭戈','san diego','加州','california'},
 {'America/Anchorage','安克雷奇','anchorage'}, {'Pacific/Honolulu','夏威夷','hawaii','honolulu'},
 {'America/Vancouver','温哥华','vancouver'}, {'America/Toronto','多伦多','toronto'},
 {'Europe/London','伦敦','london','英国','united kingdom'}, {'Europe/Berlin','法兰克福','frankfurt','柏林','berlin','德国','germany'},
 {'Europe/Paris','巴黎','paris','法国','france'}, {'Europe/Amsterdam','阿姆斯特丹','amsterdam','荷兰','netherlands'},
 {'Asia/Tokyo','东京','tokyo','大阪','osaka','日本','japan'}, {'Asia/Seoul','首尔','seoul','韩国','korea'},
 {'Asia/Singapore','新加坡','singapore'}, {'Asia/Hong_Kong','香港','hong kong'}, {'Asia/Taipei','台湾','台北','taipei','taiwan'},
 {'Australia/Sydney','悉尼','sydney'}, {'Australia/Melbourne','墨尔本','melbourne'}, {'Australia/Brisbane','布里斯班','brisbane'}, {'Australia/Perth','珀斯','perth'},
 {'Pacific/Auckland','奥克兰','auckland','新西兰','new zealand'}
}
function M.resolve(country,text,fallback)
 local haystack=tostring(text or ''):lower()
 for _,row in ipairs(rules) do
  for i=2,#row do if haystack:find(row[i],1,true) then return row[1],zones[row[1]] end end
 end
 local code=tostring(country or ''):upper()
 local name=countries[code] or fallback
 assert(name,'无法根据出口国家或城市识别时区')
 return name,zones[name]
end
function M.get(name) return zones[name] and {name=name,posix=zones[name].posix,label=zones[name].label} or nil end
return M
