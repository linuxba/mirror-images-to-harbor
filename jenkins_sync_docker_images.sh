#!/usr/bin/env bash
# set -x

cd "$(dirname "$0")" || return 1
SH_DIR=$(pwd)
ME=$0
PARAMETERS=$*
config_file="$1"
dest_registry="${DEST_HARBOR_REGISTRY:-library}"
dest_repo="${DEST_HARBOR_URL}/${dest_registry}" # 包含仓库项目的名字
thread=3                                        # 此处定义线程数
faillog="./failure.log"                         # 此处定义失败列表,注意失败列表会先被删除再重新写入
echo >>"$config_file"                           # 加行空行

#定义输出颜色函数
function red_echo() {
    #用法:  red_echo "内容"
    local what="$*"
    echo -e "$(date +%F-%T) \e[1;31m ${what} \e[0m"
}

function green_echo() {
    #用法:  green_echo "内容"
    local what="$*"
    echo -e "$(date +%F-%T) \e[1;32m ${what} \e[0m"
}

function yellow_echo() {
    #用法:  yellow_echo "内容"
    local what="$*"
    echo -e "$(date +%F-%T) \e[1;33m ${what} \e[0m"
}

function blue_echo() {
    #用法:  blue_echo "内容"
    local what="$*"
    echo -e "$(date +%F-%T) \e[1;34m ${what} \e[0m"
}

function twinkle_echo() {
    #用法:  twinkle_echo $(red_echo "内容")  ,此处例子为红色闪烁输出
    local twinkle='\e[05m'
    local what="${twinkle} $*"
    echo -e "$(date +%F-%T) ${what}"
}

function return_echo() {
    if [ $? -eq 0 ]; then
        echo -n "$* " && green_echo "成功"
        return 0
    else
        echo -n "$* " && red_echo "失败"
        return 1
    fi
}

function return_error_exit() {
    [ $? -eq 0 ] && local REVAL="0"
    local what=$*
    if [ "$REVAL" = "0" ]; then
        [ ! -z "$what" ] && { echo -n "$* " && green_echo "成功"; }
    else
        red_echo "$* 失败，脚本退出"
        exit 1
    fi
}

# 定义确认函数
function user_verify_function() {
    while true; do
        echo ""
        read -p "是否确认?[Y/N]:" Y
        case $Y in
        [yY] | [yY][eE][sS])
            echo -e "answer:  \\033[20G [ \e[1;32m是\e[0m ] \033[0m"
            break
            ;;
        [nN] | [nN][oO])
            echo -e "answer:  \\033[20G [ \e[1;32m否\e[0m ] \033[0m"
            exit 1
            ;;
        *)
            continue
            ;;
        esac
    done
}

# 定义跳过函数
function user_pass_function() {
    while true; do
        echo ""
        read -p "是否确认?[Y/N]:" Y
        case $Y in
        [yY] | [yY][eE][sS])
            echo -e "answer:  \\033[20G [ \e[1;32m是\e[0m ] \033[0m"
            break
            ;;
        [nN] | [nN][oO])
            echo -e "answer:  \\033[20G [ \e[1;32m否\e[0m ] \033[0m"
            return 1
            ;;
        *)
            continue
            ;;
        esac
    done
}

function check_image() {
    local image_name=$1
    local image_tag=$2
    local encoded
    # encoded=$(curl -s -o /dev/null -w %{url_effective} --get --data-urlencode "$image_name" "http://localhost")
    # # 移除前缀部分，只保留编码后的结果
    # encoded=$(echo $encoded | sed 's@http://localhost/?@@')
    # 二次编码 e.g. a/b -> a%2Fb -> a%252Fb
    encoded=$(echo $image_name | sed 's@/@%252F@g')
    curl -s -i --connect-timeout 10 -m 20 -u "$DEST_HARBOR_CRE_USR:$DEST_HARBOR_CRE_PSW" -k -X GET \
        -H "accept: application/json" \
        "https://$DEST_HARBOR_URL/api/v2.0/projects/$dest_registry/repositories/$encoded/artifacts/$image_tag/tags?page=1&page_size=10&with_signature=false&with_immutable_status=false" |
        grep '"name":' >/dev/null
    return $?
}

function check_skopeo() {
    command -v skopeo &>/dev/null
}

function skopeo_sync_image() {
    local line=$1
    local image_name=$2
    local image_tag=$3
    skopeo -v && skopeo copy -a \
        --dest-creds=${DEST_HARBOR_CRE_USR}:${DEST_HARBOR_CRE_PSW} \
        ${BUILD_ARGS} \
        docker://${line} \
        docker://$dest_repo/$image_name:$image_tag
    return $?
}

function docker_login() {
    # echo "${SRC_HARBOR_CRE_PSW}" | docker login --username "${SRC_HARBOR_CRE_USR}" --password-stdin $SRC_HARBOR_URL
    echo "${DEST_HARBOR_CRE_PSW}" | docker login --username "${DEST_HARBOR_CRE_USR}" --password-stdin $DEST_HARBOR_URL
}

function docker_sync_image() {
    local line=$1
    local image_name=$2
    local image_tag=$3
    docker pull $line &&
        docker tag $line $dest_repo/$image_name:$image_tag &&
        docker push $dest_repo/$image_name:$image_tag &&
        docker rmi $line &&
        docker rmi $dest_repo/$image_name:$image_tag ||
        {
            red_echo "同步镜像[ $line ]"
            echo "$line" | tee -a $faillog
        }
}

function sync_image() {
    local line=$*
    local image_name
    local image_tag
    line=$(echo "$line" | sed 's@docker.io/@@g')
    if [[ ! -z $(echo "$line" | grep '/') ]]; then
        case $dest_registry in
        library)
            image_name=$(echo $line | awk -F':|/' '{print $(NF-2)"/"$(NF-1)}')
            ;;
        *)
            image_name=$(echo $line | awk -F':|/' '{print $(NF-1)}')
            ;;
        esac
        if [[ ! -z $(echo "$image_name" | grep -w "$dest_registry") ]]; then
            image_name=$(basename $image_name)
        fi
    else
        image_name=$(echo ${line%:*})
    fi
    image_tag=$(echo $line | awk -F: '{print $2}')
    check_image $image_name $image_tag
    return_echo "检测镜像 [$image_name] 存在 "
    if [ $? -ne 0 ]; then
        echo
        yellow_echo "同步镜像[ $line ]"
        if [ "$have_skopeo" -eq 0 ]; then
            skopeo_sync_image "$line" "$image_name" "$image_tag" || docker_sync_image "$line" "$image_name" "$image_tag"
        else
            docker_sync_image "$line" "$image_name" "$image_tag"
        fi
    else
        green_echo "已存在镜像，不需要推送[$dest_repo/$image_name:$image_tag]"
        return 0
    fi
}

function usage() {
    echo "sh $ME config.txt"
}

if [ -z "$PARAMETERS" ]; then
    usage
    exit 55
fi

function trap_exit() {
    kill -9 0
}

function multi_process() {
    trap 'trap_exit;exit 2' 1 2 3 15

    if [ -f $faillog ]; then
        rm -f $faillog
    fi

    tmp_fifofile="./$$.fifo"
    mkfifo $tmp_fifofile  # 新建一个fifo类型的文件
    exec 6<>$tmp_fifofile # 将fd6指向fifo类型
    rm $tmp_fifofile

    for ((i = 0; i < $thread; i++)); do
        echo
    done >&6 # 事实上就是在fd6中放置了$thread个回车符

    exec 5<$config_file
    while read line <&5; do
        excute_line=$(echo "$line" | grep -E -v "^#")
        if [ -z "$excute_line" ]; then
            continue
        fi
        read -u6
        # 一个read -u6命令执行一次，就从fd6中减去一个回车符，然后向下执行，
        # fd6中没有回车符的时候，就停在这了，从而实现了线程数量控制
        { # 此处子进程开始执行，被放到后台
            sync_image $excute_line
            echo >&6 # 当进程结束以后，再向fd6中加上一个回车符，即补上了read -u6减去的那个
        } &
    done

    wait      # 等待所有的后台子进程结束
    exec 6>&- # 关闭df6

    if [ -f $faillog ]; then
        echo "#############################"
        red_echo "Has failure job list:"
        echo
        cat $faillog
        echo "#############################"
        exit 1
    else
        green_echo "All finish"
        echo "#############################"
    fi
}

check_skopeo
have_skopeo=$?
if [ "$have_skopeo" -ne 0 ]; then
    docker_login
fi
multi_process

exit 0
