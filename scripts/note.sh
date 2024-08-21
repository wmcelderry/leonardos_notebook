#!/bin/bash

base_dir="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" )"

function usage()
{
    cat <<-EOF
${BASH_SOURCE[0]} <mode> <label> [<value...>]

  mode is one of:
    store <label> <value...>
    retrieve <label>
    dummy <label>
EOF
}


mode="$1"
shift
label="$1"
shift
value="$*"

notebook_file="${base_dir}/data/my_notebook"



function dummy()
{
    #ensure any matching label is deleted.
    if [[ -e "${notebook_file}" ]] ; then
        sed -i "/^${label}::/d" "${notebook_file}"
    else 
        #put the KDF salt in the notebook_file.
        openssl rand -hex 16 > "${notebook_file}"
    fi

    salt="$(retrieve_salt "${notebook_file}")"

    #append the new value
    dummy_entry "${salt}" "${label}" "${value}" >> "${notebook_file}"
}

function store()
{
    local salt
    #ensure any matching label is deleted.
    if [[ -e "${notebook_file}" ]] ; then
        sed -i "/^${label}::/d" "${notebook_file}"
    else 
        #put the KDF salt in the notebook_file.
        openssl rand -hex 16 > "${notebook_file}"
    fi

    salt="$(retrieve_salt "${notebook_file}")"

    #append the new value
    encrypt_entry "${salt}" "${label}" "${value}" >> "${notebook_file}"
}


function get_entry()
{
    local label

    label="$1"
    [[ -e "${notebook_file}" ]] && sed -n "/^${label}::/{p;q}" "${notebook_file}"
}

function retrieve()
{
    val="$(get_entry "${label}")"
    salt="$(retrieve_salt "${notebook_file}")"

    if [[ -z "${val}" ]] ; then
        echo "Cannot find entry for '${label}'"
    else
        decrypt_entry "${salt}" "${val}"
    fi
}

function getkey()
{
    local salt

    salt="$1"

    echo "Enter password now:" >&2
    read  -s pass

    openssl kdf \
        -keylen 32 \
        -kdfopt "pass:${pass}" \
        -kdfopt salt:"${salt}" \
        -kdfopt n:1024 \
        -kdfopt r:8 \
        -kdfopt p:16 \
        -kdfopt maxmem_bytes:10485760 \
        SCRYPT  \
        | sed 's/://g'
}

function getdummykey()
{
    #256bit key:
    openssl rand -hex 32
}

function encrypt()
{
    local salt value

    salt="$1"
    shift
    value="$1"

    local key iv data hmac
    key="$(getkey "${salt}")"


    iv="$(openssl rand -hex 16 )"
    data="$(openssl enc -a -e -aes-256-ctr -nopad -K "${key}" -iv "${iv}" <<< "${value}" | sed -n 'H;${x;s/\n//g;p}')"
    hmac="$(openssl mac -digest SHA256 -macopt "hexkey:${key}" HMAC <<< "${data}")"

    echo "${iv}${hmac}${data}"
}

function encrypt_entry()
{
    local salt label value
    salt="$1"
    shift
    label="$1"
    shift
    value="$*"

    cipher_text=$(encrypt "${salt}" "${value}")

    echo "${label}::${cipher_text}"
}

function dummy_entry()
{
    salt="$1"
    shift
    label="$1"
    shift
    value="$*"

    key="$(getdummykey)" # just use random data as the key!
    iv="$(openssl rand -hex 16 )"
    data="$(openssl enc -a -e -aes-256-ctr -nopad -K "${key}" -iv "${iv}" <<< "${value}")"
    hmac="$(openssl mac -digest SHA256 -macopt "hexkey:${key}" HMAC <<< "${data}")"

    echo "${label}::${iv}${hmac}${data}"
}

function decrypt_entry()
{

    salt="$1"
    shift
    data="$1"

    key="$(getkey "${salt}")"

    #trim the label:
    label="${data/::*/}"
    data="${data/*::/}"

    #parse the data into constituents:
    iv="${data:0:32}"
    data_hmac="${data:32:64}"
    data="${data:96}"

    hmac="$(openssl mac -digest SHA256 -macopt "hexkey:${key}" HMAC <<< "${data}")"

    if [[ "${hmac}"  != "${data_hmac}" ]]; then
        echo "Invalid key provided for this entry."
    else
        openssl enc -d -aes-256-ctr -nopad -a  -K "${key}" -iv "${iv}" <<< "${data}"
    fi
}

function retrieve_salt()
{
    file="$1"
    #head -n 1 "${file}"
    sed -n '1{p;q}' "${file}"
}

case ${mode} in 
    store )
        store
            ;;
    retrieve )
        retrieve
        ;;
    dummy )
        dummy
        ;;
    * ) 
        usage
        ;;
esac
