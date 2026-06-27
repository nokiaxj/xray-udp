#!/usr/bin/bash

USERNAME=$(whoami)
USERNAME_DOMAIN=$(whoami | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]//g')
WORKDIR="/home/${USERNAME}/domains/${USERNAME_DOMAIN}.serv00.net/public_nodejs"
WSPATH=${WSPATH:-'serv00'}
UUID=${UUID:-'de04add9-5c68-8bab-950c-08cd5320df18'}
WEB_USERNAME=${WEB_USERNAME:-'admin'}
WEB_PASSWORD=${WEB_PASSWORD:-'password'}

set_language() {
    devil lang set english
}

set_domain_dir() {
    local DOMAIN="${USERNAME_DOMAIN}.serv00.net"
    if devil www list | grep nodejs | grep "/domains/${DOMAIN}"; then
        if [ ! -d ${WORKDIR}/public ]; then
            git clone https://github.com/k0baya/mikutap ${WORKDIR}/public
        fi
        return 0
    else
        echo "正在检测 NodeJS 环境，请稍候..."
        nohup devil www del ${DOMAIN} >/dev/null 2>&1
        devil www add ${DOMAIN} nodejs /usr/local/bin/node22
        rm -rf ${WORKDIR}/public
        git clone https://github.com/k0baya/mikutap ${WORKDIR}/public
    fi
}

reserve_port() {
    local port_list
    local tcp_count
    local udp_count
    local current_port
    local max_attempts
    local attempts
    local increment

    # 内部函数：尝试添加 TCP 端口
    local add_tcp_port
    add_tcp_port() {
        local port=$1
        # 假设 devil 命令成功返回 0，失败返回非 0
        devil port add tcp "$port" >/dev/null 2>&1
    }

    # 内部函数：尝试添加 UDP 端口
    local add_udp_port
    add_udp_port() {
        local port=$1
        devil port add udp "$port" >/dev/null 2>&1
    }

    # 内部函数：删除特定 UDP 端口
    local delete_udp_port
    delete_udp_port() {
        local port=$1
        local result=$(devil port del udp "$port")
        echo "删除多余 UDP 端口 $port: $result"
    }

    # 内部函数：删除特定 TCP 端口
    local delete_tcp_port
    delete_tcp_port() {
        local port=$1
        local result=$(devil port del tcp "$port")
        echo "删除多余 TCP 端口 $port: $result"
    }

    # 更新端口列表及计数的工具函数
    update_port_list() {
        port_list=$(devil port list)
        tcp_count=$(echo "$port_list" | grep -c 'tcp')
        udp_count=$(echo "$port_list" | grep -c 'udp')
    }

    # 1. 初始化列表
    update_port_list

    # 2. 【清理多余端口】
    # 如果 TCP 端口超过 2 个，循环删除多余的，直到只剩 2 个
    while [ "$tcp_count" -gt 2 ]; do
        EXTRA_TCP=$(echo "$port_list" | grep 'tcp' | awk 'NR==1{print $1}')
        delete_tcp_port "$EXTRA_TCP"
        update_port_list
    done

    # 如果 UDP 端口超过 1 个，循环删除多余的，直到只剩 1 个
    while [ "$udp_count" -gt 1 ]; do
        EXTRA_UDP=$(echo "$port_list" | grep 'udp' | awk 'NR==1{print $1}')
        delete_udp_port "$EXTRA_UDP"
        update_port_list
    done

    # 3. 随机选择起始端口及方向
    local start_port=$(( RANDOM % 63077 + 1024 ))  # 1024-64000之间的随机数
    if [ $start_port -le 32512 ]; then
        current_port=$start_port
        increment=1
    else
        current_port=$start_port
        increment=-1
    fi

    max_attempts=100 
    attempts=0

    # 4. 核心循环：只要 TCP 不足 2 个，或者 UDP 不足 1 个，就继续申请
    while [ "$tcp_count" -lt 2 ] || [ "$udp_count" -lt 1 ]; do
        
        # 如果缺 TCP，优先补齐 TCP
        if [ "$tcp_count" -lt 2 ]; then
            if add_tcp_port "$current_port"; then
                echo "成功添加预留 TCP 端口: $current_port"
                update_port_list
            fi
        # 如果 TCP 够了但缺 UDP，补齐 UDP
        elif [ "$udp_count" -lt 1 ]; then
            if add_udp_port "$current_port"; then
                echo "成功添加预留 UDP 端口: $current_port"
                update_port_list
            fi
        fi

        # 无论成功与否，端口号走向下一个，尝试次数 +1
        current_port=$((current_port + increment))
        attempts=$((attempts + 1))

        # 熔断机制
        if [ $attempts -ge $max_attempts ]; then
            echo "超过最大尝试次数，无法补齐 2个TCP 和 1个UDP 端口"
            exit 1
        fi
    done

    # 5. 最终获取并打印结果
    update_port_list
    TCP1=$(echo "$port_list" | grep 'tcp' | awk 'NR==1{print $1}')
    TCP2=$(echo "$port_list" | grep 'tcp' | awk 'NR==2{print $1}')
    UDP1=$(echo "$port_list" | grep 'udp' | awk 'NR==1{print $1}')
    
    echo "--------------------------------"
    echo "当前端口状态完全达标："
    echo "TCP 端口数量: $tcp_count (标准: 2)"
    echo "UDP 端口数量: $udp_count (标准: 1)"
    echo "具体端口列表 -> TCP: $TCP1, $TCP2 | UDP: $UDP1"
    echo "--------------------------------"
}



generate_dotenv() {

    generate_uuid() {
    local uuid
    uuid=$(uuidgen -r)
    while [[ ${uuid:0:1} =~ [0-9] ]]; do
        uuid=$(uuidgen -r)
    done
    echo "$uuid"
    }

    printf "请输入 ARGO_AUTH（必填）："
    read -r ARGO_AUTH
    printf "请输入 ARGO_DOMAIN_VL（必填）："
    read -r ARGO_DOMAIN_VL
    echo "请在Cloudflare中为隧道添加域名 ${ARGO_DOMAIN_VL} 指向 HTTP://localhost:${TCP1},添加完成请按回车继续"
    read
    printf "请输入 ARGO_DOMAIN_TR（必填）："
    read -r ARGO_DOMAIN_TR
    echo "请在Cloudflare中为隧道添加域名 ${ARGO_DOMAIN_VM} 指向 HTTP://localhost:${TCP2},添加完成请按回车继续"
    read
    printf "请输入 UUID（默认值：f6e23862-46a0-4418-98e9-a7d7c0b5df43）："
    read -r UUID
    printf "请输入 WSPATH（默认值：serv00）："
    read -r WSPATH
    printf "请输入 WEB_USERNAME（默认值：admin）："
    read -r WEB_USERNAME
    printf "请输入 WEB_PASSWORD（默认值：password）："
    read -r WEB_PASSWORD

    if [ -z "${ARGO_AUTH}" ] || [ -z "${ARGO_DOMAIN_VL}" ] || [ -z "${ARGO_DOMAIN_TR}" ]; then
    echo "Error! 所有选项都不能为空！"
    rm -rf ${WORKDIR}/*
    rm -rf ${WORKDIR}/.*
    exit 1
    fi

    if [ -z "${UUID}" ]; then
        echo "正在生成 UUID..."
        UUID=$(generate_uuid)
    fi
    if [ -z "${WSPATH}" ]; then
        WSPATH='serv00'
    fi
    if [ -z "${WEB_USERNAME}" ]; then
        WEB_USERNAME='admin'
    fi
    if [ -z "${WEB_PASSWORD}" ]; then
        WEB_PASSWORD='password'
    fi

    cat > ${WORKDIR}/.env << EOF
ARGO_AUTH=${ARGO_AUTH}
ARGO_DOMAIN_VL=${ARGO_DOMAIN_VL}
ARGO_DOMAIN_TR=${ARGO_DOMAIN_TR}
UUID=${UUID}
WSPATH=${WSPATH}
WEB_USERNAME=${WEB_USERNAME}
WEB_PASSWORD=${WEB_PASSWORD}
EOF
}

get_app() {
    echo "正在下载 app.js 请稍候..."
    wget -t 10 -qO ${WORKDIR}/app.js https://github.com/nokiaxj/xray-udp/raw/refs/heads/main/app.js
    if [ $? -ne 0 ]; then
        echo "app.js 下载失败！请检查网络情况！"
        exit 1
    fi
    echo "正在下载 package.json 请稍候..."
    wget -t 10 -qO ${WORKDIR}/package.json https://github.com/nokiaxj/xray-udp/raw/refs/heads/main/package.json
    if [ $? -ne 0 ]; then
        echo "package.json 下载失败！请检查网络情况！"
        exit 1
    fi

    echo "正在安装依赖..."
    nohup npm22 install > /dev/null 2>&1
}

get_core() {
    local TMP_DIRECTORY=$(mktemp -d)
    local ZIP_FILE="${TMP_DIRECTORY}/Xray-freebsd-64.zip"
    echo "正在下载 Web.js 请稍候..."
    wget -t 10 -qO "$ZIP_FILE" https://github.com/nokiaxj/xray-udp/raw/refs/heads/main/Xray-freebsd-64.zip
    if [ $? -ne 0 ]; then
        echo "Web.js 安装失败！请检查网络情况！"
        exit 1
    else
        unzip -qo "$ZIP_FILE" -d "$TMP_DIRECTORY"
        install -m 755 "${TMP_DIRECTORY}/xray" "${WORKDIR}/web.js"
        rm -rf "$TMP_DIRECTORY"
    fi
    
    echo "正在下载 GEOSITE 数据库，请稍候..."
    wget -t 10 -qO ${WORKDIR}/geosite.dat https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat
    if [ $? -ne 0 ]; then
        echo "GEOSITE 数据库下载失败！请检查网络情况！"
        exit 1
    fi
        
    echo "正在下载 GEOIP 数据库，请稍候..."
    wget -t 10 -qO ${WORKDIR}/geoip.dat https://github.com/nokiaxj/xray-udp/raw/refs/heads/main/geoip.dat
    if [ $? -ne 0 ]; then
        echo "GEOIP 数据库下载失败！请检查网络情况！"
        exit 1
    fi
}

generate_config() {	
    cat > ${WORKDIR}/config.json << EOF
{
    "log": {
        "loglevel": "error"
    },
    "inbounds":[
        {
            "port":${TCP1},
            "listen":"127.0.0.1",
            "protocol":"vless",
            "settings":{
                "clients":[
                    {
                        "id":"${UUID}",
                        "level":0
                    }
                ],
                "decryption":"none"
            },
            "streamSettings":{
                "network":"ws",
                "security":"none",
                "wsSettings":{
                    "path":"/${WSPATH}-vless"
                }
            }
        },
        {
            "port":${TCP2},
            "listen":"127.0.0.1",
            "protocol":"trojan",
            "settings":{
                "clients":[
                    {
                        "password":"${UUID}"
                    }
                ]
            },
            "streamSettings":{
                "network":"ws",
                "security":"none",
                "wsSettings":{
                    "path":"/${WSPATH}-trojan"
                }
            }
        },
		{
           "port": ${UDP1},
           "listen": "0.0.0.0",
           "protocol": "hysteria",
           "settings": {
                "auth": "${UUID}"
           },
           "streamSettings": {
           "network": "hysteria",
           "security": "tls", // 1. 开启 TLS 安全性
           "hysteriaSettings": {
               "version": 2
            },
           "tlsSettings": {
              "certificates": [
                {
                "certificateFile": "cert.pem", // 2. 填入你的证书绝对路径
                "keyFile": "private.key"      // 3. 填入你的私钥绝对路径
                }
              ]
            }
         }
      }
    ],
    "outbounds": [
      {
        "protocol": "freedom",
        "tag": "direct",
        "settings": {
          "domainStrategy": "UseIPv4" // 强制优先使用 IPv4，防止直连 IPv6 失败
        }
      },
      {
        "tag": "warp-ipv6",
        "protocol": "wireguard",
        "settings": {
          "secretKey": "wBBUpigxbXdv8NGRLHD0BnMfBhHlfujf9s8/BG8BLVo=", // 填入您的 Private Key
          "address": [
            "172.16.0.2/32",
            "2606:4700:110:8e62:2f62:eb69:3d97:c6a5/128" // 填入 WARP 分配的内网 IPv6 地址
          ],
          "peers": [
            {
              "publicKey": "bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo=", // WARP 官方公钥
              "endpoint": "162.159.192.1:2408" // 使用 IPv4 地址连接 WARP 节点
            }
          ],
          "mtu": 1280 // 建议设置为 1280 以保证在各种网络下的兼容性
        }
      }
    ],
    "routing": {
    "domainStrategy": "IPOnDemand", // 遇到域名时，根据需要解析 IP 以匹配路由规则
    "rules": [
      {
        "type": "field",
        "outboundTag": "warp-ipv6",
        "ip": [
          "::/0" // 匹配所有目标为 IPv6 的流量
        ]
      }
    ]
  }
}
EOF
}

generate_argo() {
  cat > argo.sh << ABC
#!/usr/bin/bash

USERNAME=\$(whoami)
USERNAME_DOMAIN=\$(whoami | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]//g')
WORKDIR="/home/\${USERNAME}/domains/\${USERNAME_DOMAIN}.serv00.net/public_nodejs"

cd \${WORKDIR}
source \${WORKDIR}/.env

check_file() {
    wget -t 10 https://cloudflared.bowring.uk/binaries/cloudflared-freebsd-latest.7z

    if [ \$? -ne 0 ]; then
        echo "Cloudflared 客户端安装失败！请检查 hosts 文件是否屏蔽了下载地址！" > list
        exit 1
    else
        7z x cloudflared-freebsd-latest.7z -bb > /dev/null \
        && rm cloudflared-freebsd-latest.7z \
        && mv -f ./temp/* ./cloudflared \
        && rm -rf temp \
        && chmod +x cloudflared
    fi
}


run() {
        if [[ -n "\${ARGO_AUTH}" && -n "\${ARGO_DOMAIN_VL}" && -n "\${ARGO_DOMAIN_TR}" ]]; then
        if [[ "\$ARGO_AUTH" =~ TunnelSecret ]]; then
            echo "\$ARGO_AUTH" | sed 's@{@{"@g;s@[,:]@"\0"@g;s@}@"}@g' > \${WORKDIR}/tunnel.json
            cat > \${WORKDIR}/tunnel.yml << EOF
tunnel: \$(sed "s@.*TunnelID:\(.*\)}@\1@g" <<< "\$ARGO_AUTH")
credentials-file: \${WORKDIR}/tunnel.json
protocol: http2

ingress:
  - hostname: \$ARGO_DOMAIN_VL
    service: http://localhost:\${TCP1}
  - hostname: \$ARGO_DOMAIN_TR
    service: http://localhost:\${TCP2}
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF
            nohup ./cloudflared tunnel --edge-ip-version auto --config tunnel.yml run > /dev/null 2>&1 &
        elif [[ "\$ARGO_AUTH" =~ ^[A-Z0-9a-z=]{120,250}$ ]]; then
            nohup ./cloudflared tunnel --edge-ip-version auto --protocol http2 run --token \${ARGO_AUTH} > /dev/null 2>&1 &
        fi
    else
        echo '请设置环境变量 \$ARGO_AUTH 和 \$ARGO_DOMAIN_TR、\$ARGO_DOMAIN_VL > \${WORKDIR}/list
        exit 1
    fi
    }

export_list() {
   cat > list << EOF
*******************************************
V2-rayN:
----------------------------
vless://${UUID}@upos-sz-mirrorcf1ov.bilivideo.com:443?path=%2F${WSPATH}-vless%3Fed%3D2560&security=tls&encryption=none&host=\${ARGO_DOMAIN_VL}&type=ws&sni=\${ARGO_DOMAIN_VL}#Argo-k0baya-Vless
----------------------------
----------------------------
trojan://${UUID}@upos-sz-mirrorcf1ov.bilivideo.com:443?path=%2F${WSPATH}-trojan%3Fed%3D2560&security=tls&host=\${ARGO_DOMAIN_TR}&type=ws&sni=\${ARGO_DOMAIN_TR}#Argo-k0baya-Trojan
----------------------------
hysteria2://${UUID}@host=\${USERNAME_DOMAIN}.serv00.net:${UDP1}?sni=${USERNAME_DOMAIN}.serv00.net&insecure=1&allowInsecure=1#hysteria2%E8%8A%82%E7%82%B9
*******************************************
小火箭:
----------------------------
vless://${UUID}@upos-sz-mirrorcf1ov.bilivideo.com:443?encryption=none&security=tls&type=ws&host=\${ARGO_DOMAIN_VL}&path=/${WSPATH}-vless?ed=2560&sni=\${ARGO_DOMAIN_VL}#Argo-k0baya-Vless
----------------------------
----------------------------
trojan://${UUID}@upos-sz-mirrorcf1ov.bilivideo.com:443?peer=\${ARGO_DOMAIN_TR}&plugin=obfs-local;obfs=websocket;obfs-host=\${ARGO_DOMAIN_TR};obfs-uri=/${WSPATH}-trojan?ed=2560#Argo-k0baya-Trojan
*******************************************
Clash:
----------------------------
- {name: Argo-k0baya-Vless, type: vless, server: upos-sz-mirrorcf1ov.bilivideo.com, port: 443, uuid: ${UUID}, tls: true, servername: \${ARGO_DOMAIN_VL}, skip-cert-verify: false, network: ws, ws-opts: {path: /${WSPATH}-vless?ed=2560, headers: { Host: \${ARGO_DOMAIN_VL}}}, udp: true}
----------------------------
----------------------------
- {name: Argo-k0baya-Trojan, type: trojan, server: upos-sz-mirrorcf1ov.bilivideo.com, port: 443, password: ${UUID}, udp: true, tls: true, sni: \${ARGO_DOMAIN_TR}, skip-cert-verify: false, network: ws, ws-opts: { path: /${WSPATH}-trojan?ed=2560, headers: { Host: \${ARGO_DOMAIN_TR} } } }
*******************************************
EOF

echo \$(echo -n "vless://${UUID}@upos-sz-mirrorcf1ov.bilivideo.com:443?path=%2F${WSPATH}-vless%3Fed%3D2560&security=tls&encryption=none&host=\${ARGO_DOMAIN_VL}&type=ws&sni=\${ARGO_DOMAIN_VL}#Argo-k0baya-Vless
hysteria2://${UUID}@host=\${ARGO_DOMAIN_HY2}:443?sni=${ARGO_DOMAIN_HY2}&insecure=1&allowInsecure=1#hysteria2%E8%8A%82%E7%82%B9
trojan://${UUID}@upos-sz-mirrorcf1ov.bilivideo.com:443?path=%2F${WSPATH}-trojan%3Fed%3D2560&security=tls&host=\${ARGO_DOMAIN_TR}&type=ws&sni=\${ARGO_DOMAIN_TR}#Argo-k0baya-Trojan" | base64 ) > sub

}
[ ! -e \${WORKDIR}/cloudflared ] && check_file
run
export_list
ABC
}

set_language
set_domain_dir
reserve_port

cd ${WORKDIR}
[ ! -e ${WORKDIR}/.env ] && generate_dotenv
[ ! -e ${WORKDIR}/app.js ] || [ ! -e ${WORKDIR}/package.json ] && get_app
[ ! -e ${WORKDIR}/web.js ] && get_core
generate_config
generate_argo

[ -e ${WORKDIR}/argo.sh ] && echo "请访问 https://${USERNAME_DOMAIN}.serv00.net/status 获取服务端状态, 当 cloudflared 与 web.js 正常运行后，访问 https://${USERNAME_DOMAIN}.serv00.net/list 获取配置"
