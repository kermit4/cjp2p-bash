#!/bin/bash -eu
trap 'echo $0 failed at $BASH_COMMAND ;echo $0 failed at $BASH_COMMAND >&2 ' ERR
export RUST_BACKTRACE=1
export  RUST_LOG=warn
coproc ./target/release/cjp2p-bash
cd /dev/shm
mkdir -p ${0##*/}
cd ${0##*/}
exec 10<&${COPROC[0]}    
exec 11<&${COPROC[1]}
{ 
    echo 159.69.54.127:24254
    echo 24
    echo -n '[{"PleaseSendPeers":{}}]' 
} >&11
offset_wanted=0
eof=$2
mkdir -p incoming/$1 # this starts the transfer
BLOCK_SIZE=$((0xa000))
req() {
    ((offset_wanted<eof)) && {
            echo requesting $offset_wanted >&2
            echo 159.69.54.127:24254 
            message="[{\"PleaseSendContent\":{\"id\":\"$id\",\"length\":$BLOCK_SIZE,\"offset\":$offset_wanted}}]"
            let offset_wanted+=$BLOCK_SIZE
            while [[ -s incoming/$id/$offset_wanted ]];do 
                let offset_wanted+=$BLOCK_SIZE
            done
            echo ${#message}
            echo -n "$message"
        } >&11
    true
}
id=$(ls incoming/|head -1)
while true;do
    if ! read -t 1  src <&10    ;then # bump
        [[ $id ]] && {
            ((offset_wanted>eof)) && 
            (($(find incoming/$id/ -mindepth 1 |wc -l) < $(((eof+BLOCK_SIZE-1)/BLOCK_SIZE)))) && {  # missing parts
                offset_wanted=0
            }
            ((offset_wanted>eof)) && {  # done
                    mkdir -p complete
                    find incoming/$id/ -mindepth 1|sort -nk3 -t / |xargs cat > complete/$id
                    rm -rf incoming/$id
                    echo $id done
                    id=$(ls incoming/|head -1)
                }
            req
        }
        continue
    fi
    read len <&10
    messages=$(mktemp -p . messages.XXXXXXXXX)
    head -${len}c <&10 > $messages
#    jq -C < messages.json
#    [{"Content":{"base64":"vLTtmB1Ot1dumq1Hscila3uKZF71KU2E3mDH","eof":1073741824,"id":"1024M","offset":204791808}}]
    { 
        content=$(mktemp -p . content.XXXXXXXXX)
        if jq -re '.[].Content'  < $messages > $content ;then 
            offset_in=$( jq -r '.offset' < $content )
            echo received $offset_in >&2 window $((offset_wanted - $offset_in))
            id=$(jq -r '.id' < $content )
            [[ -d incoming/$id ]] || continue
            file=incoming/$id/$offset_in
            [[ -s $file ]] || { 
                    jq -r '.base64' < $content  | 
                    base64 -d  > $file 2>/dev/null
            }
        fi
        rm $content $messages
    }&
    req
    ((((offset_wanted/BLOCK_SIZE)%51)==0)) && req # increase packets in flight, so its faster than blocksize/rtt 
done
