#!/bin/bash

config="singbox.json"
installpath="$HOME"
# 引入 utils.sh
if [[ -e "$installpath/serv00-play" ]]; then
  source ${installpath}/serv00-play/utils.sh
fi

VMPORT=$(jq -r ".VMPORT" $config)
HY2PORT=$(jq -r ".HY2PORT" $config)
HY2IP=$(jq -r ".HY2IP" $config)
UUID=$(jq -r ".UUID" $config)
WSPATH=$(jq -r ".WSPATH" $config)

ARGO_AUTH=$(jq -r ".ARGO_AUTH" $config)
ARGO_DOMAIN=$(jq -r ".ARGO_DOMAIN" $config)
TUNNEL_NAME=$(jq -r ".TUNNEL_NAME" $config)
GOOD_DOMAIN=$(jq -r ".GOOD_DOMAIN" $config)
SOCKS5_PORT=$(jq -r ".SOCKS5_PORT" $config)
SOCKS5_USER=$(jq -r ".SOCKS5_USER" $config)
SOCKS5_PASS=$(jq -r ".SOCKS5_PASS" $config)
user="$(whoami)"

if [ -z $1 ]; then
  type=$(jq -r ".TYPE" $config)
else
  type=$1
fi

keep=$2

run() {
  if ps aux | grep cloudflared | grep -v "grep" >/dev/null; then
    return
  fi
  if [[ "${ARGO_AUTH}" != "null" && "${ARGO_DOMAIN}" != "null" ]]; then
    nohup ./cloudflared tunnel --edge-ip-version auto --protocol http2 run --token ${ARGO_AUTH} >/dev/null 2>&1 &
  elif [[ "$ARGO_DOMAIN" != "null" && "$TUNNEL_NAME" != "null" ]]; then
    nohup ./cloudflared tunnel run $TUNNEL_NAME >/dev/null 2>&1 &
  else
    echo "未有tunnel相关配置！"
    return 1
  fi
}

uploadList() {
  local token="$1"
  local content="$2"
  local user="${user,,}"
  local url="${linkBaseurl}/addlist?token=$token"
  local encode_content=$(echo -n "$content" | base64 -w 0)

  curl -X POST "$url" \
    -H "Content-Type: application/json" \
    -d "{\"content\":\"$encode_content\",
    \"user\":\"$user\"}"

  if [[ $? -eq 0 ]]; then
    return 0
  else
    return 1
  fi
}

export_list() {
  user="$(whoami)"
  
  echo ""
  yellow "正在获取当前可用节点列表..."
  show_ip_status
  
  local hostname=$(hostname)
  local host_number=$(echo "$hostname" | awk -F'[s.]' '{print $2}')
  local hostmain=$(getDoMain)
  if isSmall; then
      hostmain="small.pl"
  else
      hostmain="serv00.com"
  fi
  local hosts_list=("cache${host_number}.${hostmain}" "web${host_number}.${hostmain}" "$hostname")

  local selected_addr=""
  local final_remark=""
  
  while true; do
      echo ""
      yellow "请选择 SOCKS5/VMess 链接使用的地址 (默认为本机域名):"
      read -p "请输入序号 No. (直接回车默认选本机): " select_idx
      
      if [[ -z "$select_idx" ]]; then
          select_idx=3
      fi

      if [[ ! "$select_idx" =~ ^[0-9]+$ ]] || [[ "$select_idx" -lt 1 ]] || [[ "$select_idx" -gt ${#hosts_list[@]} ]]; then
          red "无效序号，请重新输入!"
          continue
      fi

      local idx=$((select_idx-1))
      local chosen_domain=${hosts_list[$idx]}
      local chosen_ip=${localIPs[$idx]} 

      echo "你选择了: $chosen_domain (IP: $chosen_ip)"
      
      if [[ "$chosen_ip" == "null" || -z "$chosen_ip" ]]; then
          red "警告：该节点 IP 获取失败，建议换一个。"
      fi

      echo "请选择链接中填写的地址类型:"
      echo "1. 使用域名 ($chosen_domain)"
      echo "2. 使用 IP ($chosen_ip)"
      read -p "请选择 [1]: " type_choice
      
      if [[ "$type_choice" == "2" ]]; then
          if [[ "$chosen_ip" == "null" || -z "$chosen_ip" ]]; then
             red "IP 无效，强制使用域名!"
             selected_addr=$chosen_domain
             final_remark="($chosen_domain)"
          else
             selected_addr=$chosen_ip
             final_remark="(IP-$chosen_domain)"
          fi
      else
          selected_addr=$chosen_domain
          final_remark="($chosen_domain)"
      fi
      break
  done

  # ==============================================================================
  # 核心修复 1: 提取 SHA256 证书指纹 (如果证书存在)
  # ==============================================================================
  local cert_fingerprint=""
  local cert_path="${installpath}/serv00-play/singbox/cert.pem"
  
  if [[ -f "$cert_path" ]]; then
      # 提取指纹并去掉冒号，转换为小写或大写（大部分客户端兼容去冒号格式）
      cert_fingerprint=$(openssl x509 -noout -fingerprint -sha256 -inform pem -in "$cert_path" | cut -d "=" -f 2 | tr -d ':')
  fi

  if [[ "$HY2IP" != "::" ]]; then
    myip=${HY2IP}
  else
    myip="$(curl -s icanhazip.com)"
  fi
  
  if [[ "$GOOD_DOMAIN" == "null" ]]; then
    GOOD_DOMAIN="www.bing.com" # 建议与默认生成的证书域名保持一致
  fi
  
  vmessname="Argo-vmess-$user-$final_remark"
  hy2name="Hy2-$user"
  
  # ==============================================================================
  # 核心修复 2: 规范化 VMess JSON 配置
  # 移除 allowInsecure 隐患，对于自签证书，由于 vmess 协议原生不支持指纹传递，
  # 我们只能尽量提供规范的 TLS 参数。如果用户客户端报错，仍需填入指纹。
  # ==============================================================================
  
  VMESSWS="{ \"v\":\"2\", \"ps\": \"Vmessws-$user-$final_remark\", \"add\":\"$selected_addr\", \"port\":\"443\", \"id\": \"${UUID}\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"${GOOD_DOMAIN}\", \"path\": \"/${WSPATH}?ed=2048\", \"tls\": \"tls\", \"sni\": \"${GOOD_DOMAIN}\", \"alpn\": \"\", \"fp\": \"chrome\"}"
  
  ARGOVMESS="{ \"v\": \"2\", \"ps\": \"$vmessname\", \"add\": \"$GOOD_DOMAIN\", \"port\": \"443\", \"id\": \"${UUID}\", \"aid\": \"0\", \"scy\": \"auto\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"${ARGO_DOMAIN}\", \"path\": \"/${WSPATH}?ed=2048\", \"tls\": \"tls\", \"sni\": \"${ARGO_DOMAIN}\", \"alpn\": \"\", \"fp\": \"chrome\" }"
  
  # ==============================================================================
  # 核心修复 3: Hysteria2 链接优化
  # v2rayN 新版支持在 Hysteria2 URI 中传递 pinSHA256 参数。
  # ==============================================================================
  local hy2_params="sni=www.bing.com&alpn=h3"
  if [[ -n "$cert_fingerprint" ]]; then
      # 如果提取到了指纹，则加入 pinSHA256 参数，移除 insecure=1
      hy2_params="${hy2_params}&pinSHA256=${cert_fingerprint}"
  else
      # 兼容老配置的降级处理
      hy2_params="${hy2_params}&insecure=1"
  fi
  
  hysteria2="hysteria2://$UUID@$myip:$HY2PORT/?${hy2_params}#$hy2name"
  
  socks5="https://t.me/socks?server=${selected_addr}&port=${SOCKS5_PORT}&user=${SOCKS5_USER}&pass=${SOCKS5_PASS}"
  
  proxyip="proxyip://${SOCKS5_USER}:${SOCKS5_PASS}@${selected_addr}:${SOCKS5_PORT}"

  # ==============================================================================
  # 核心修复 4: 终端输出优化
  # ==============================================================================
  cat >list <<EOF
*******************************************
【节点安全配置提示】
----------------------------
当前服务器证书指纹 (SHA256):
${cert_fingerprint:-"未找到本地证书"}

* Hysteria2 节点已自动集成指纹 (pinSHA256)，导入即可使用。
* VMess 节点如遇 TLS 验证报错，请在客户端手动将上述指纹填入 [pinnedPeerCertSha256] 字段。
----------------------------

V2-rayN / Clash 节点链接:
----------------------------

$([[ "$type" =~ ^(1.1|3.1|4.4|2.4)$ ]] && echo "vmess://$(echo ${ARGOVMESS} | base64 -w0)")
$([[ "$type" =~ ^(1.2|3.2|4.5|2.5)$ ]] && echo "vmess://$(echo ${VMESSWS} | base64 -w0)")
$([[ "$type" =~ ^(2|3.3|3.1|3.2|4.4|4.5)$ ]] && echo $hysteria2 && echo "")
$([[ "$type" =~ ^(1.3|2.4|2.5|3.3|4.4|4.5)$ ]] && echo $socks5 && echo "")
$([[ "$type" =~ ^(1.3|2.4|2.5|3.3|4.4|4.5)$ ]] && echo $proxyip && echo "")

EOF
  cat list
  
  if [[ -e "${installpath}/serv00-play/linkalive/linkAlive.sh" ]]; then
    local domain=$(getUserDoMain)
    domain="${domain,,}"
    if [[ -e "${installpath}/domains/$domain/public_nodejs/config.json" ]]; then
      token=$(jq -r ".token" "${installpath}/domains/$domain/public_nodejs/config.json")
      if [[ -n "$token" ]]; then
        content=$(cat ./list | grep -E "vmess|hyster")
        if uploadList "$token" "$content"; then
          echo " "
        fi
      fi
    fi
  fi
}

if [ "$keep" = "list" ]; then
  export_list
  exit 0
fi

if [[ "$type" =~ ^(1|3|1.1|3.1|4.4|2.4)$ ]]; then
  run
fi

if [[ "$type" =~ ^(1.2|1.3|2|2.5|3.2|3.3|4.5)$ ]]; then
  r=$(ps aux | grep cloudflare | grep -v grep | awk '{print $2}')
  if [ -n "$r" ]; then
    kill -9 $r
  fi
  chmod +x ./serv00sb
  if ! ps aux | grep serv00sb | grep -v "grep" >/dev/null; then
    nohup ./serv00sb run -c ./config.json >/dev/null 2>&1 &
  fi
elif [[ "$type" =~ ^(1|3|1.1|3.1|4.4|2.4)$ ]]; then
  chmod +x ./serv00sb
  if ! ps aux | grep serv00sb | grep -v "grep" >/dev/null; then
    nohup ./serv00sb run -c ./config.json >/dev/null 2>&1 &
  fi
fi

if [ -z "$keep" ]; then
  export_list
fi
exit 0
