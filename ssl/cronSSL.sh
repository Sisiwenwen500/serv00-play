#!/bin/bash

installpath="$HOME"
domain=$1
host="$(hostname | cut -d '.' -f 1)"
user=$(whoami)

# 逻辑说明：将主机名 s0/s1 转换为 web0/web1
sno=${host/s/web}

# 尝试通过主机名匹配获取 IP (Serv00/Small.pl 标准方式)
webIp=$(devil vhost list public | grep "$sno" | awk '{print $1}')

# --- 新增：Small.pl 兼容性兜底 ---
# 如果上面的方法没获取到 IP，则直接获取列表中的第一个 IP
if [[ -z "$webIp" ]]; then
    webIp=$(devil vhost list public | awk 'NR>2 {print $1; exit}')
fi
# -------------------------------

if [[ -z "$webIp" ]]; then
    echo "错误：无法获取 Web IP，无法申请证书。"
    exit 1
fi

resp=$(devil ssl www add $webIp le le $domain)

cd ${installpath}/serv00-play/ssl

if [[ "$resp" =~ .*succesfully.*$ ]]; then
  # 申请成功，删除 crontab 任务
  crontab -l | grep -v "$domain" >tmpcron
  crontab tmpcron
  rm -rf tmpcron
  
  # 确定配置文件路径
  if [[ -f "../config.json" ]] && grep -q "telegram_token" "../config.json"; then
    config="../config.json"
  else
    config="../msg.json"
  fi
  
  # 发送通知
  if [ -e "$config" ]; then
    TELEGRAM_TOKEN=$(jq -r ".telegram_token // empty" "$config")
    TELEGRAM_USERID=$(jq -r ".telegram_userid // empty" "$config")
    
    if [[ -n "$TELEGRAM_TOKEN" && -n "$TELEGRAM_USERID" ]]; then
      msg="Host:$host, user:$user, 你的域名($domain)申请的SSL证书已下发,请查收!"
      cd $installpath/serv00-play
      export TELEGRAM_TOKEN="$TELEGRAM_TOKEN" TELEGRAM_USERID="$TELEGRAM_USERID"
      # 确保 tgsend.sh 有执行权限
      chmod +x ./tgsend.sh
      ./tgsend.sh "$msg"
    fi
  fi
elif [[ "$resp" =~ .*already.*$ ]]; then
  echo "域名($domain)的SSL证书已存在,无需重复申请!"
  # 即使是已存在，也应该删除定时任务，避免死循环
  crontab -l | grep -v "$domain" >tmpcron
  crontab tmpcron
  rm -rf tmpcron
else
  echo "申请SSL证书失败,请检查域名($domain)是否正确! 返回信息: $resp"
fi
