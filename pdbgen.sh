#!/bin/bash
#
# 使用说明
#
# 功能：并行构造TPC-H测试数据集，每个表生成多个测试文件分片，便于后续并行导入
#
# 使用方法：
# 1. 将脚本程序和dbgen工具放在同一个目录下
# 2. 确认maxthd/sleep等参数是否要调整
# 3. 运行脚本
# 例如要生成SF10测试数据集，采用下面方法即可
# ./pdbgen.sh 10 > ./pdbgen.log 2>&1
#

#最大并发数，默认设置为可用逻辑CPU数-2，可自行调整
# 方法1：使用lscpu获取CPU核心数
maxthd=$(lscpu 2>/dev/null | grep '^CPU(s)' | awk '{print $NF}')

# 检查是否获取成功（不为空且是数字）
if [[ -z "$maxthd" ]] || ! [[ "$maxthd" =~ ^[0-9]+$ ]]; then
    echo "警告：lscpu方法获取失败，尝试/proc/cpuinfo方法"
    # 方法2：回退到/proc/cpuinfo
    maxthd=$(grep -c '^processor' /proc/cpuinfo 2>/dev/null)
    # 再次检查
    if [[ -z "$maxthd" ]] || ! [[ "$maxthd" =~ ^[0-9]+$ ]]; then
        echo "错误：无法获取CPU核心数，使用默认值4"
        maxthd=4
    fi
fi

# 安全地减去2，确保最小值不小于1
if [[ "$maxthd" -gt 2 ]]; then
    maxthd=$((maxthd - 2))
else
    maxthd=1
    echo "提示：CPU核心数较少($maxthd)，并发数设置为1"
fi

echo "最大并发数设置为: $maxthd"

#当达到最大并发数时轮询等待时长
sleep=1

cat <<EOF
TPC-H Population Generator

USAGE:
./pdbgen.sh <N>

Options
===========================
<N> -- set Scale Factor (SF) to  <N> (default: 1)

EOF

#设置Scale Factor，默认值为1
sf=1
if [ ! -z "$1" ] && grep '^[[:digit:]]' <<< "$1" > /dev/null; then
  sf=`expr $1 + 0`
  echo "TPC-H SF=${sf} test data generating"
  sleep ${sleep}
else
  sf=1
  echo "You did not specify the option <N>, the default value is 1"
  echo "TPC-H SF=${sf} test data generating"
  sleep ${sleep}
fi

cat <<EOF
...
...
...
EOF

#不同表分片基数
tbls=(
'c 2'  #customer
'L 60' #lineitem
'n 1'  #nation
'O 15' #orders
'P 2'  #part
'S 8'  #partsupp
'r 1'  #region
's 1'  #supplier
)

c=1
for i in "${tbls[@]}"
do
  tbl=`echo ${i} | awk '{print $1}'`
  chunk=`echo ${i} | awk '{print $2}'`
  #实际分片数还要乘以Scale Factor
  chunk=`expr ${chunk} \* ${sf}`

  for j in $(seq 1 $chunk)
  do
    echo "TBL: ${tbl}, CHUNK: ${chunk}, j: {$j}, c:${c}"
    #控制并发数
    while [ `ps -ef|grep -v grep|grep -c dbgen` -gt ${maxthd} ]
    do
      sleep ${sleep}
    done

    if [ ${chunk} -eq 1 ] ; then
      ./dbgen -vf -s ${sf} -C ${chunk} -T ${tbl} > /dev/null 2>&1 &
    else
      ./dbgen -vf -s ${sf} -S ${j} -C ${chunk} -T ${tbl} > /dev/null 2>&1 &
    fi
    c=`expr $c + 1`
  done
done
