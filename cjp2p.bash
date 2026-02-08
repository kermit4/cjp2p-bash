#!/bin/bash -eu
trap 'echo $0 failed at $BASH_COMMAND ;echo $0 failed at $BASH_COMMAND >&2 ' ERR
export RUST_BACKTRACE=1
export  RUST_LOG=warn
coproc ./target/release/cjp2p-bash
#cd /dev/shm
mkdir -p ${0##*/}.dir
cd ${0##*/}.dir
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
            #echo requesting $offset_wanted >&2
            echo ${src:-159.69.54.127:24254}
            message="[{\"PleaseSendContent\":{\"id\":\"$id\",\"length\":$BLOCK_SIZE,\"offset\":$offset_wanted}}]"
            let offset_wanted+=$BLOCK_SIZE
            while [[ -s incoming/$id/$offset_wanted ]];do 
                let offset_wanted+=$BLOCK_SIZE
            done
            echo ${#message}
            echo -n "$message"
        } >&11
    [ . ]
}
id=$(ls incoming/|head -1) # currrently does only one file at a time
while true;do
    if ! read -rt 1  src <&10    ;then # bump
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
    read -r len <&10
    messages=$(mktemp -p . m.XXXX)
    head -c $len <&10 > $messages
#    jq -C < $messages
#    [{"Content":{"base64":"vLTtmB1Ot1dumq1Hscila3uKZF71KU2E3mDH","eof":1073741824,"id":"1024M","offset":204791808}}]
    if read -r offset_in id_ < <(jq -er  '.[]|select(.Content)|.Content|(.offset |tostring) +" " + .id' < $messages) && 
        [ $id_ ]; then
        id=${id_##*/} # security
        #echo received $id $offset_in >&2 window $((offset_wanted - $offset_in))
        file=incoming/$id/$offset_in
        jq -er '.[]|select(.Content)|.Content.base64' < $messages  |
            base64 -d  > $file 2>/dev/null  || [ . ]
        req
        ((((offset_wanted/BLOCK_SIZE)%101)==0)) && req # increase packets in flight, so its faster than blocksize/rtt
    fi
    rm -rf $messages
done
