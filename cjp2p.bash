#!/bin/bash -eu
debug() {
    echo "$*" >&2
}
trap 'echo $0 failed at $BASH_COMMAND ;echo $0 failed at $BASH_COMMAND >&2 ' ERR
export RUST_BACKTRACE=1
export  RUST_LOG=warn
coproc ./target/release/cjp2p-bash
#cd /dev/shm
mkdir -p ${0##*/}.dir
cd ${0##*/}.dir
mkdir -p peers
>peers/159.69.54.127:24254
exec 10<&${COPROC[0]}    
exec 11<&${COPROC[1]}
offset_wanted=0
eof=$2
mkdir -p incoming/$1 # this starts the transfer
BLOCK_SIZE=$((0xa000))
#[   {     "PleaseSendPeers": {}   },   {     "PleaseReturnThisMessage": {       "sent_at": 11151.745030629     }   } ]
please_send_peers() {
    src=$(ls peers/ -tr|tail -20|sort -R|tail -1)
    debug requesting peers from $src
    message="[{\"PleaseSendPeers\":{}}]"
    echo $src
    echo ${#message}
    echo -n "$message"
}
req() {
    ((offset_wanted<eof)) || return 0
    [[ $src ]] || src=$(ls peers/ -tr|tail -20|sort -R|tail -1)
    debug requesting $offset_wanted from $src window $((offset_wanted - ${offset_in:-0}))
    message="[{\"PleaseSendContent\":{\"id\":\"$id\",\"length\":$BLOCK_SIZE,\"offset\":$offset_wanted}}]"
    let offset_wanted+=$BLOCK_SIZE
    while [[ -s incoming/$id/$offset_wanted ]];do 
        let offset_wanted+=$BLOCK_SIZE
    done
    echo $src
    echo ${#message}
    echo -n "$message"
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
            req >&11
            src= please_send_peers >&11
        }
        continue
    fi
    touch peers/$src
    read -r len <&10
    messages=$(mktemp -p . m.XXXX)
    head -c $len <&10 > $messages
#    jq -C < $messages
#    [{"Content":{"base64":"vLTtmB1Ot1dumq1Hscila3uKZF71KU2E3mDH","eof":1073741824,"id":"1024M","offset":204791808}}]
    if read -r offset_in id_ < <(jq -er  '.[]|select(.Content)|.Content|(.offset |tostring) +" " + .id' < $messages) && 
        [ $id_ ]; then
        id=${id_##*/} # security
        offset_in=${offset_in##*/} # security
        debug received $id $offset_in window $((offset_wanted - $offset_in))
        file=incoming/$id/$offset_in
        if [[ -s $file ]];then
            debug duplicate received block  $file 
        else
            jq -er '.[]|select(.Content)|.Content.base64' < $messages  |
                base64 -d  > $file 2>/dev/null  || [ . ]
        fi
        req >&11
        (((RANDOM%101)==0)) && req >&11 # increase packets in flight, so its faster than blocksize/rtt
#[   {     "PleaseSendPeers": {}   },   {     "PleaseReturnThisMessage": {       "sent_at": 11151.745030629     }   } ]
    elif read -r returned_message < <(jq -cer  '.[]|select(.PleaseReturnThisMessage)|.PleaseReturnThisMessage' < $messages) &&  [ $returned_message ] ;then
        message="[{\"ReturnedMessage\":$returned_message}]"
        debug sending to $src "$message" 
        {
            echo $src
            echo ${#message}
            echo -n "$message"
        } >&11
        (((RANDOM%3)==0)) && src= req >&11 # try other sources sometimes
    elif read -r peers < <(jq -cer  '.[]|.Peers' < $messages) &&  [ $peers ] ;then
        comm -2 -3 <(jq -cer '.peers[]' <<<$peers |sort ) <(ls peers/ ) |tee >(debug $(wc -l) new peers from $src: ) | (cd peers;xargs --no-run-if-empty touch -d @1 )
    else
        (((RANDOM%11)==0)) && please_send_peers >&11
        (((RANDOM%3)==0)) && src= req >&11 # try other sources sometimes
        echo -n $src said\  ;jq -cC . < $messages || cat $messages
    fi 
    rm -rf $messages
done
