#!/bin/bash

RED='\033[0;91m'
GREEN='\033[0;92m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;96m'
WHITE='\033[0;37m'
RESET='\033[0m'
yellow() {
	echo -e "${YELLOW}$1${RESET}"
}
green() {
	echo -e "${GREEN}$1${RESET}"
}
red() {
	echo -e "${RED}$1${RESET}"
}
installpath="$HOME"
baseurl="https://ss.fkj.pp.ua"
linkBaseurl="https://la.fkj.pp.ua"

checknezhaAgentAlive() {
	if ps aux | grep nezha-agent | grep -v "grep" >/dev/null; then
		return 0
	else
		return 1
	fi
}

checkvmessAlive() {
	local c=0
	if ps aux | grep serv00sb | grep -v "grep" >/dev/null; then
		((c++))
	fi

	if ps aux | grep cloudflared | grep -v "grep" >/dev/null; then
		((c++))
	fi

	if [ $c -eq 2 ]; then
		return 0
	fi

	return 1 # 有一个或多个进程不在运行

}

#返回0表示成功， 1表示失败
#在if条件中，0会执行，1不会执行
checkProcAlive() {
	local procname=$1
	if ps aux | grep "$procname" | grep -v "grep" >/dev/null; then
		return 0
	else
		return 1
	fi
}

stopProc() {
	local procname=$1
	r=$(ps aux | grep "$procname" | grep -v "grep" | awk '{print $2}')
	if [ -z "$r" ]; then
		return 0
	else
		kill -9 $r
	fi
	echo "已停掉$procname!"
	return 0
}

checkSingboxAlive() {
	local c=0
	if ps aux | grep serv00sb | grep -v "grep" >/dev/null; then
		((c++))
	fi

	if ps aux | grep cloudflare | grep -v "grep" >/dev/null; then
		((c++))
	fi

	if [ $c -eq 2 ]; then
		return 0
	fi

	return 1 # 有一个或多个进程不在运行

}

checkMtgAlive() {
	if ps aux | grep mtg | grep -v "grep" >/dev/null; then
		return 0
	else
		return 1
	fi
}

stopNeZhaAgent() {
	r=$(ps aux | grep nezha-agent | grep -v "grep" | awk '{print $2}')
	if [ -z "$r" ]; then
		return 0
	else
		kill -9 $r
	fi
	echo "已停掉nezha-agent!"
}

writeWX() {
	has_fd=$(echo "$config_content" | jq 'has("wxsendkey")')
	if [ "$has_fd" == "true" ]; then
		wx_sendkey=$(echo "$config_content" | jq -r ".wxsendkey")
		read -p "已有 WXSENDKEY ($wx_sendkey), 是否修改? [y/n] [n]:" input
		input=${input:-n}
		if [ "$input" == "y" ]; then
			read -p "请输入 WXSENDKEY:" wx_sendkey
		fi
		json_content+="  \"wxsendkey\": \"${wx_sendkey}\", \n"
	else
		read -p "请输入 WXSENDKEY:" wx_sendkey
		json_content+="  \"wxsendkey\": \"${wx_sendkey}\", \n"
	fi

}

writeTG() {
	has_fd=$(echo "$config_content" | jq 'has("telegram_token")')
	if [ "$has_fd" == "true" ]; then
		tg_token=$(echo "$config_content" | jq -r ".telegram_token")
		read -p "已有 TELEGRAM_TOKEN ($tg_token), 是否修改? [y/n] [n]:" input
		input=${input:-n}
		if [ "$input" == "y" ]; then
			read -p "请输入 TELEGRAM_TOKEN:" tg_token
		fi
		json_content+="  \"telegram_token\": \"${tg_token}\", \n"
	else
		read -p "请输入 TELEGRAM_TOKEN:" tg_token
		json_content+="  \"telegram_token\": \"${tg_token}\", \n"
	fi

	has_fd=$(echo "$config_content" | jq 'has("telegram_userid")')
	if [ "$has_fd" == "true" ]; then
		tg_userid=$(echo "$config_content" | jq -r ".telegram_userid")
		read -p "已有 TELEGRAM_USERID ($tg_userid), 是否修改? [y/n] [n]:" input
		input=${input:-n}
		if [ "$input" == "y" ]; then
			read -p "请输入 TELEGRAM_USERID:" tg_userid
		fi
		json_content+="  \"telegram_userid\": \"${tg_userid}\", \n"
	else
		read -p "请输入 TELEGRAM_USERID:" tg_userid
		json_content+="  \"telegram_userid\": \"${tg_userid}\",\n"
	fi
}

cleanCron() {
	echo "" >null
	crontab null
	rm null
}

delCron() {
	crontab -l | grep -v "keepalive" >mycron
	crontab mycron >/dev/null 2>&1
	rm mycron
}

addCron() {
	local tm=$1
	crontab -l | grep -v "keepalive" >mycron
	echo "*/$tm * * * * bash ${installpath}/serv00-play/keepalive.sh > /dev/null 2>&1 " >>mycron
	crontab mycron >/dev/null 2>&1
	rm mycron

}

get_webip() {
	# 获取主机名称，例如：s2.serv00.com
	local hostname=$(hostname)

	# 提取主机名称中的数字，例如：2
	local host_number=$(echo "$hostname" | awk -F'[s.]' '{print $2}')

	# 构造主机名称的数组
	local hosts=("web${host_number}.$(getDoMain)" "cache${host_number}.$(getDoMain)")

	# 初始化最终 IP 变量
	local final_ip="$(devil vhost list | grep web | awk '{print $1}')"
	local hostmain=$(getDoMain)
	hostmain="${hostmain%.com}"
	# 遍历主机名称数组
	for host in "${hosts[@]}"; do
		# 获取 API 返回的数据
		local response=$(curl -s "${baseurl}/api/getip?host=$host&type=$hostmain")

		# 检查返回的结果是否包含 "not found"
		if [[ "$response" =~ "not found" ]]; then
			continue
		fi

		# 提取第一个字段作为 IP，并检查第二个字段是否为 "Accessible"
		local ip=$(echo "$response" | awk -F "|" '{ if ($2 == "Accessible") print $1 }')
		# webxx.serv00.com域名对应的ip作为兜底ip
		if [[ "$host" == "web${host_number}.$(getDoMain)" ]]; then
			final_ip=$(echo "$response" | awk -F "|" '{print $1}')
		fi

		# 如果找到了 "Accessible"，返回 IP
		if [[ -n "$ip" ]]; then
			echo "$ip"
			return
		fi
	done

	echo "$final_ip"
}

get_ip() {
	# 获取主机名称，例如：s2.serv00.com
	local hostname=$(hostname)

	# 提取主机名称中的数字，例如：2
	local host_number=$(echo "$hostname" | awk -F'[s.]' '{print $2}')

	# 构造主机名称的数组
	local hosts=("cache${host_number}.$(getDoMain)" "web${host_number}.$(getDoMain)" "$hostname")

	# 初始化最终 IP 变量
	local final_ip="$(curl -s icanhazip.com)"

	local hostmain=$(getDoMain)
	hostmain="${hostmain%.com}"
	# 遍历主机名称数组
	for host in "${hosts[@]}"; do
		# 获取 API 返回的数据
		local response=$(curl -s "${baseurl}/api/getip?host=$host&type=$hostmain")

		# 检查返回的结果是否包含 "not found"
		if [[ "$response" =~ "not found" ]]; then
			continue
		fi

		# 提取第一个字段作为 IP，并检查第二个字段是否为 "Accessible"
		local ip=$(echo "$response" | awk -F "|" '{ if ($2 == "Accessible") print $1 }')

		# 如果找到了 "Accessible"，返回 IP
		if [[ -n "$ip" ]]; then
			echo "$ip"
			return
		fi

		final_ip=$ip
	done

	echo "$final_ip"
}

# 判断是否为 serv00
isServ00() {
    [[ $(hostname) == *"serv00"* ]]
}

# 新增：判断是否为 small.pl
isSmall() {
    [[ $(hostname) == *"small"* ]]
}

# 修改：获取主域名（增加 small.pl 支持）
getDoMain() {
    if isServ00; then
        echo -n "serv00.com"
    elif isSmall; then
        echo -n "small.pl"
    else
        echo -n "hostuno.com"
    fi
}

# 修改：获取用户域名（增加 smallhost.pl 支持）
getUserDoMain() {
    local proc=$1
    local baseDomain=""
    user="$(whoami)"
    
    if isServ00; then
        baseDomain="$user.serv00.net"
    elif isSmall; then
        # Small.pl 的用户默认二级域名通常是 username.smallhost.pl
        baseDomain="$user.smallhost.pl"
    else
        baseDomain="$user.useruno.com"
    fi
    
    if [[ -n "$proc" ]]; then
        echo -n "$proc.$baseDomain"
    else
        echo -n "$baseDomain"
    fi
}

#获取端口
getPort() {
	local type=$1
	local opts=$2

	local key="$type|$opts"
	#echo "key: $key"
	#port list中查找，如果没有随机分配一个
	if [[ -n "${port_array["$key"]}" ]]; then
		#echo "找到list中的port"
		echo "${port_array["$key"]}"
	else
		# echo "devil port add $type random $opts"
		rt=$(devil port add $type random $opts)
		if [[ "$rt" =~ .*succesfully.*$ || "$rt" =~ .*Ok.*$ ]]; then
			loadPort
			if [[ -n "${port_array["$key"]}" ]]; then
				echo "${port_array["$key"]}"
			else
				echo "failed"
			fi
		else
			echo "failed"
		fi
	fi
}

randomPort() {
	local type=$1
	local opts=$2
	port=""
	#echo "type:$type, opts:$opts"
	read -p "是否自动分配${opts}端口($type)？[y/n] [y]:" input
	input=${input:-y}
	if [[ "$input" == "y" ]]; then
		port=$(getPort $type $opts)
		if [[ "$port" == "failed" ]]; then
			read -p "自动分配端口失败，请手动输入${opts}端口:" port
		else
			green "自动分配${opts}端口为:${port}"
		fi
	else
		read -p "请输入${opts}端口($type):" port
	fi
}

declare -A port_array
#检查是否可以自动分配端口
loadPort() {
	output=$(devil port list)

	port_array=()
	# 解析输出内容
	index=0
	while read -r port typ opis; do
		# 跳过标题行
		if [[ "$port" =~ "Port" ]]; then
			continue
		fi
		#echo "port:$port,typ:$typ, opis:$opis"
		if [[ "$port" =~ "Brak" || "$port" == "No" ]]; then
			echo "未分配端口"
			return 0
		fi
		# 将 Typ 和 Opis 合并并存储到数组中
		if [[ -n "$typ" ]]; then
			# 如果 Opis 为空则用空字符串代替
			opis=${opis:-""}
			combined="${typ}|${opis}"
			port_array["$combined"]="$port"
			# echo "port_array 读入 key=$combined, value=$port"
			((index++))
		fi
	done <<<"$output"

	return 0
}

cleanPort() {
	output=$(devil port list)
	while read -r port typ opis; do
		# 跳过标题行
		if [[ "$typ" == "Type" ]]; then
			continue
		fi
		if [[ "$port" == "Brak" || "$port" == "No" ]]; then
			return 0
		fi
		if [[ -n "$typ" ]]; then
			devil port del $typ $port >/dev/null 2>&1
		fi
	done <<<"$output"
	return 0
}

ISIDR=1
ISFILE=0
ISVIP=1
NOTVIP=0
checkDownload() {
	local file=$1
	local is_dir=${2:-0}
	local passwd=${3:-"fkjyyds666"}
	local vipflag=${4:-0}
	local filegz="$file.gz"

	if [[ $is_dir -eq 1 ]]; then
		filegz="$file.tar.gz"
	fi

	#检查并下载核心程序
	if [[ ! -e $file ]] || [[ $(file $file) == *"text"* ]]; then
		echo "正在下载 $file..."
		if [[ $vipflag -eq 1 ]]; then
			url="https://gfg.fkj.pp.ua/app/vip/$filegz?pwd=$passwd"
		else
			url="https://gfg.fkj.pp.ua/app/serv00/$filegz?pwd=$passwd"
		fi
		#echo "url:$url"
		curl -L -sS --max-time 20 -o $filegz "$url"

		if file $filegz | grep -q "text"; then
			echo "无法正确下载!!!"
			rm -f $filegz
			return 1
		fi
		if [ -e $filegz ]; then
			if [[ $is_dir -eq 1 ]]; then
				tar -zxf $filegz
			else
				gzip -d $filegz
			fi
		else
			echo "下载失败，可能是网络问题."
			return 1
		fi
		#下载失败
		if [[ $is_dir -eq 0 && ! -e $file ]]; then
			echo "无法下载核心程序，可能网络问题，请检查！"
			return 1
		fi
		# 设置可执行权限
		if [[ $is_dir -eq 0 ]]; then
			chmod +x "$file"
		fi
		echo "下载完毕!"
	fi
	return 0
}

# 对json文件字段进行插入或修改
# usage: upInsertFd jsonfile fieldname value
upInsertFd() {
	local jsonfile=$1
	local field=$2
	local value=$3

	jq --arg field "$field" --arg value "$value" '
        if has($field) then 
                .[$field] = $value
        else 
                . + {($field): $value}
        end
        ' "$jsonfile" >tmp.json && mv tmp.json "$jsonfile"

	return $?
}

# 针对singbox.json, 对指定字段进行修改
upSingboxFd() {
	local jsonfile=$1
	local array_name=$2
	local selector_key=$3
	local selector_value=$4
	local field_path=$5
	local value=$6

	jq --arg selector_key "$selector_key" \
		--arg selector_value "$selector_value" \
		--arg field_path "$field_path" \
		--arg value "$value" "
         (.$array_name[] | select(.$selector_key == \$selector_value) | .[\$field_path]) = \$value
     " "$jsonfile" >tmp.json && mv tmp.json "$jsonfile"

	return $?
}

# php默认配置文件操作
PHPCONFIG_FILE="phpconfig.json"
# 判断JSON文件是否存在，若不存在则创建并初始化
initialize_json() {
	if [ ! -f "$PHPCONFIG_FILE" ]; then
		echo '{"domains": []}' >"$PHPCONFIG_FILE"
	fi
}

# 添加新域名
add_domain() {
	local new_domain="$1"
	local webip="$2"

	# 初始化JSON文件（如果不存在的话）
	initialize_json

	# 读取当前的JSON配置文件并检查域名是否已存在
	if grep -q "\"$new_domain\"" "$PHPCONFIG_FILE"; then
		echo "域名 '$new_domain' 已存在！"
		return 1
	fi

	# 使用jq来处理JSON，添加新的域名到domains数组
	#jq --arg domain "$new_domain" '.domains += [$domain]' "$PHPCONFIG_FILE" >temp.json && mv temp.json "$PHPCONFIG_FILE"
	jq ".domains += [{\"domain\": \"$domain\", \"webip\": \"$webip\"}]" "$PHPCONFIG_FILE" >"$PHPCONFIG_FILE.tmp" && mv "$PHPCONFIG_FILE.tmp" "$PHPCONFIG_FILE"
	#echo "域名 '$new_domain' 添加成功！"
	return 0
}

# 删除域名
delete_domain() {
	local domain_to_delete="$1"

	# 初始化JSON文件（如果不存在的话）
	initialize_json

	# 读取当前的JSON配置文件并检查域名是否存在
	if ! grep -q "\"$domain_to_delete\"" "$PHPCONFIG_FILE"; then
		echo "域名 '$domain_to_delete' 不存在！"
		return 1
	fi

	local webip=$(jq -r ".domains[] | select(.domain == \"$domain\") | .webip" "$PHPCONFIG_FILE")
	# 使用jq来处理JSON，删除指定的域名
	jq "del(.domains[] | select(.domain == \"$domain\"))" "$PHPCONFIG_FILE" >"$PHPCONFIG_FILE.tmp" && mv "$PHPCONFIG_FILE.tmp" "$PHPCONFIG_FILE"
	local domainPath="$installpath/domains/$domain"
	echo "正在删除域名相关服务,请等待..."
	rm -rf "$domainPath"
	resp=$(devil ssl www del $webip $domain)
	resp=$(devil www del $domain --remove)
	echo "已卸载域名[$domain_to_delete]相关服务!"
	return 0
}

# 判断domains数组是否为空
check_domains_empty() {
	initialize_json

	local domains_count=$(jq '.domains | length' "$PHPCONFIG_FILE")

	if [ "$domains_count" -eq 0 ]; then
		return 0
	else
		return 1
	fi
}
print_domains() {
	yellow "----------------------------"
	green "域名\t\t|\t服务IP"
	yellow "----------------------------"

	# 使用jq格式化输出
	jq -r '.domains[] | "\(.domain)\t|\(.webip)"' "$PHPCONFIG_FILE"
}

delete_all_domains() {
	initialize_json

	jq -r '.domains[] | "\(.domain)\t\(.webip)"' "$PHPCONFIG_FILE" | while read -r domain webip; do
		echo "域名: $domain, 服务IP: $webip"
		delete_domain "$domain"
	done
}

get_one_domain() {
	initialize_json

	local first_domain=$(jq -r '.domains[0].domain' "$PHPCONFIG_FILE")
	echo "$first_domain"
}

download_from_net() {
	local app=$1

	case $app in
	"alist")
		download_from_github_release "AlistGo" "alist" "alist-freebsd-amd64.tar.gz"
		;;
	"nezha-agent")
		download_from_github_release "nezhahq" "agent" "nezha-agent_freebsd_amd64.zip"
		;;
	"nezha-dashboard")
		download_from_github_release "frankiejun" "freebsd-nezha" "dashboard.gz"
		;;
	esac
}

check_update_from_net() {
	local app=$1

	case $app in
	"alist")
		local current_version=$(./alist version | grep "Version: v" | awk '{print $2}')
		if ! check_from_github "AlistGo" "alist" "$current_version"; then
			echo "未发现新版本!"
			return 1
		fi
		download_from_github_release "AlistGo" "alist" "alist-freebsd-amd64.tar.gz"
		;;
	"nezha-agent")
		local current_version="v"$(./nezha-agent -v | awk '{print $3}')
		if ! check_from_github "nezhahq" "agent" "$current_version"; then
			echo "未发现新版本!"
			return 1
		fi
		download_from_github_release "nezhahq" "agent" "nezha-agent_freebsd_amd64.zip"
		;;
	"nezha-dashboard")
		local current_version=$(./nezha-dashboard -v)
		if ! check_from_github "frankiejun" "freebsd-nezha" "$current_version"; then
			echo "未发现新版本!"
			return 1
		fi
		download_from_github_release "frankiejun" "freebsd-nezha" "dashboard.gz"
		;;
	esac
}

check_from_github() {
	local user=$1
	local repository=$2
	local local_version="$3"
	local url="https://github.com/${user}/${repository}"
	local latestUrl="$url/releases/latest"

	latest_version=$(curl -sL $latestUrl | sed -n 's/.*tag\/\(v[0-9.]*\).*/\1/p' | head -1)
	#latest_version=$(curl -sL "https://api.github.com/repos/${user}/${repository}/releases/latest" | jq -r '.tag_name // empty')
	if [[ "$local_version" != "$latest_version" ]]; then
		echo "发现新版本: $latest_version，当前版本: $local_version, 正在更新..."
		return 0
	fi
	return 1
}

download_allcode_from_github_release() {
	local user=$1
	local repository=$2

	local url="https://github.com/${user}/${repository}"
	local latestUrl="$url/releases/latest"
	local latest_version=$(curl -sL $latestUrl | sed -n 's/.*tag\/\(v[0-9.]*\).*/\1/p' | head -1)
	local download_url="${url}/archive/refs/tags/${latest_version}.zip"

	curl -sL -o "${repository}-${latest_version}.zip" "$download_url"
	if [[ ! -e "${repository}-${latest_version}.zip" || -n $(file "${repository}-${latest_version}.zip" | grep "text") ]]; then
		echo "下载 ${repository}-${latest_version}.zip 文件失败!"
		return 1
	fi

	# 原地解压缩
	# 创建临时目录tmp
	mkdir -p tmp
	local clean_version="${latest_version#v}"
	local target_dir="${repository}-${clean_version}"
	#echo "target_dir: $target_dir"
	case "${repository}-${latest_version}.zip" in
	*.zip)
		unzip -o "${repository}-${latest_version}.zip" -d tmp
		# 使用cp命令替代mv命令，避免"Directory not empty"错误
		cp -r "tmp/${target_dir}/"* tmp/
		rm -rf "tmp/${target_dir}"
		;;
	*.tar.gz)
		tar -xzf "${repository}-${latest_version}.tar.gz" --xform="s|^[^/]*|tmp|"
		;;
	*)
		echo "不支持的文件格式"
		return 1
		;;
	esac
	rm -rf "${repository}-${latest_version}.zip"
}

download_from_github_release() {
	local user=$1
	local repository=$2
	local zippackage="$3"

	local url="https://github.com/${user}/${repository}"
	local latestUrl="$url/releases/latest"

	local latest_version=$(curl -sL $latestUrl | sed -n 's/.*tag\/\(v[0-9.]*\).*/\1/p' | head -1)
	#latest_version=$(curl -sL "https://api.github.com/repos/${user}/${repository}/releases/latest" | jq -r '.tag_name // empty')
	local download_url="${url}/releases/download/$latest_version/$zippackage"
	curl -sL -o "$zippackage" "$download_url"
	if [[ ! -e "$zippackage" || -n $(file "$zippackage" | grep "text") ]]; then
		echo "下载 $zippackage 文件失败!"
		return 1
	fi
	# 原地解压缩
	case "$zippackage" in
	*.zip)
		unzip -o "$zippackage" -d .
		;;
	*.tar.gz | *.tgz)
		tar -xzf "$zippackage"
		;;
	*.tar.bz2 | *.tbz2)
		tar -xjf "$zippackage"
		;;
	*.tar.xz | *.txz)
		tar -xJf "$zippackage"
		;;
	*.gz)
		gzip -d "$zippackage"
		;;
	*.tar)
		tar -xf "$zippackage"
		;;
	*)
		echo "不支持的文件格式: $zippackage"
		return 1
		;;
	esac

	if [[ $? -ne 0 ]]; then
		echo "解压 $zippackage 文件失败!"
		return 1
	fi

	rm -rf "$zippackage"
	echo "下载并解压 $zippackage 成功!"
	return 0
}

clean_all_domains() {
	echo "正在清理域名..."
	output=$(devil www list)
	if echo "$output" | grep -q "No elements to display"; then
		echo "没有发现在用域名."
		return 0
	fi
	domains=($(echo "$output" | awk 'NF && NR>2 {print $1}'))

	for domain in "${domains[@]}"; do
		devil www del $domain --remove
	done
	echo "域名清理完毕!"
}

create_default_domain() {
	echo "正在创建默认域名..."
	local domain=$(getUserDoMain)
	domain="${domain,,}"
	devil www add $domain php
	echo "默认域名创建成功!"
}

clean_all_dns() {
	echo "正在清理DNS..."
	output=$(devil dns list)
	if echo "$output" | grep -q "No elements to display"; then
		echo "没有发现在用DNS."
		return 0
	fi
	domains=($(echo "$output" | awk 'NF && NR>2 {print $1}'))

	for domain in "${domains[@]}"; do
		devil dns del $domain
	done
	echo "DNS清理完毕!"
}

# -----------------------------------------------------------
# 修改版: show_ip_status
# 功能: 
# 1. 自动识别 Small.pl 并进行本地 DNS 解析
# 2. 利用 ping0.cc 进行 GFW 状态检测 (无需自建服务器)
# 3. 生成 ITDog 直达链接方便复核
# -----------------------------------------------------------
# 请替换 utils.sh 中的 show_ip_status 函数
show_ip_status() {
    localIPs=()
    useIPs=()
    local hostname=$(hostname)
    local host_number=$(echo "$hostname" | awk -F'[s.]' '{print $2}')
    
    local hosts=("cache${host_number}.$(getDoMain)" "web${host_number}.$(getDoMain)" "$hostname")
    local hostmain=$(getDoMain)
    hostmain="${hostmain%.com}"

    echo "正在检测 IP 及 GFW 状态，请稍候 (使用 ping0.cc 数据源)..."
    yellow "------------------------------------------------------------------------"
    printf "%-3s | %-20s | %-15s | %-10s | %-10s\n" "No." "Host" "IP Address" "GFW Status" "Check Link"
    yellow "------------------------------------------------------------------------"

    local i=0
    for host in "${hosts[@]}"; do
        ((i++))
        
        local ip=""
        local status="Unknown"
        local check_link=""

        # --- 获取 IP ---
        if isSmall; then
            ip=$(drill -Q A "$host" | grep -E '^[0-9.]+$' | head -n 1)
        else
            local response=$(curl -s "${baseurl}/api/getip?host=$host&type=$hostmain")
            if [[ ! "$response" =~ "not found" ]]; then
                ip=$(echo "$response" | awk -F "|" '{print $1 }')
            fi
        fi

        # --- 核心修改：无论成功失败，都处理 localIPs 数组以保持索引对齐 ---
        if [[ -n "$ip" && "$ip" != "Resolution Failed" && "$ip" != "No IP Found" ]]; then
            localIPs+=("$ip")
            useIPs+=("$ip") 
            
            check_link="https://www.itdog.cn/tcping/${ip}:443"
            local p0_content=$(curl -s --max-time 5 "https://ping0.cc/ip/${ip}")
            
            if echo "$p0_content" | grep -q "国内.*正常"; then
                status="${GREEN}Accessible${RESET}"
            elif echo "$p0_content" | grep -q "国内.*屏蔽"; then
                status="${RED}Blocked${RESET}"
            else
                status="LocalDNS"
            fi
        else
            ip="No IP Found"
            status="${RED}Error${RESET}"
            # 🔥 关键点：存入 null 占位，确保序号与数组下标一致
            localIPs+=("null") 
        fi

        printf "%-3d | %-20s | %-15s | %-10s | %-10s\n" "$i" "$host" "$ip" "$status" "Wait"
    done
    yellow "------------------------------------------------------------------------"
}

stop_sing_box() {
	cd ${installpath}/serv00-play/singbox
	if [ -f killsing-box.sh ]; then
		chmod 755 ./killsing-box.sh
		./killsing-box.sh
	else
		echo "请先安装serv00-play!!!"
		return
	fi
	echo "已停掉sing-box!"
}

start_sing_box() {
	cd ${installpath}/serv00-play/singbox

	if [[ ! -e "singbox.json" ]]; then
		red "请先进行配置!"
		return 1
	fi

	if ! checkDownload "serv00sb"; then
		return
	fi
	if ! checkDownload "cloudflared"; then
		return
	fi

	if checkSingboxAlive; then
		red "sing-box 已在运行，请勿重复操作!"
		return 1
	else #启动可能需要cloudflare，此处表示cloudflare和sb有一个不在线，所以干脆先杀掉再重启。
		chmod 755 ./killsing-box.sh
		./killsing-box.sh
	fi

	if chmod +x start.sh && ! ./start.sh; then
		red "sing-box启动失败！"
		exit 1
	fi
	sleep 2
	if checkProcAlive "serv00sb"; then
		yellow "启动成功!"
	else
		red "启动失败!"
	fi

}

checkCronNameStatus() {
	if checkCronName $1; then
		green "在线"
	else
		red "离线"
	fi
}
checkCronName() {
	local name=$1
	if crontab -l | grep -q "$name"; then
		return 0
	else
		return 1
	fi
}
