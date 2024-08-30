#!/bin/bash

base_dir="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" )"

function usage()
{
    cat <<-EOF
${BASH_SOURCE[0]} <mode> <label> [<value...>]

  mode is one of:
    "store"|"s"     <label> <value...>
    "retrieve"|"r"  <label>
    "del"|"rm"      <label>
    "change_password"|"cpw"
    "list"|"l"

  Store adds a new entry
  retrieve recovers an entry
  del or rm removes an entry
  change_password allows changing the password
  list lists the entries
EOF
}


mode="$1"
shift
label="$1"
shift
value="$*"

notebook_file="${base_dir}/data/my_primary_notebook"



function create_notebook_file()
{
    local file="${1}"
    local primary_key_hex="$(openssl rand -hex 32)"

    gen_password_line "${primary_key_hex}" >> "${file}"

    echo "${primary_key_hex}"
}

function change_password()
{
    local file="${notebook_file}"

    echo "Enter existing password to unlock the key material:"
    local primary_key_hex="$(retrieve_pkey "${file}")"

    if [[ -z "${primary_key_hex}" ]] ; then
        echo "Failed to unlock the key."
        return
    fi

    echo "Enter new password for future operation:"
    local password_line="$(gen_password_line "${primary_key_hex}")"

    # confirm the password to ensure it can be unlocked!
    echo "Re-enter the new password to confirm correct spelling!"
    local conf_pkey="$(retrieve_pkey_from_line "${password_line}")"

    if [[ "${conf_pkey,,*}" != "${primary_key_hex,,*}" ]] ; then
        echo "New passwords do not match!"
    else
        sed -i "1s!.*!${password_line}!g" "${file}"
    fi
}


function gen_password_line()
{
    local primary_key_hex="$1"

    #put the KDF salt and primary key in the notebook_file.
    salt="$(openssl rand -hex 16)"

    echo  -n "${salt}"

    #store the primary key, protected by the password
    encrypt "${salt}" "${primary_key_hex}"
}

function delete_entry()
{
    local label notebook_file

    label="$1"
    notebook_file="$2"

    sed -i "/^${label}::/d" "${notebook_file}"
}

function store()
{
    local salt

    if [[ -e "${notebook_file}" ]] ; then
        delete_entry "${label}" "${notebook_file}"
        primary_key_hex="$(retrieve_pkey "${notebook_file}")"
        if [[ -z "${primary_key_hex}" ]] ; then
            echo "Incorrect key for encrypting."
            return
        fi
    else
        primary_key_hex="$(create_notebook_file "${notebook_file}")"
    fi

    #echo encrypt_entry_with_key "${label}" "${primary_key_hex}" "${value}"
    encrypt_entry_with_key "${label}" "${primary_key_hex}" "${value}" >> "${notebook_file}"
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
    primary_key_hex="$(retrieve_pkey "${notebook_file}")"

    if [[ -z "${primary_key_hex}" ]] ; then
        echo "Incorrect key for decrypting."
        return
    fi

    if [[ -z "${val}" ]] ; then
        echo "Cannot find entry for '${label}'"
    else
        decrypt_entry_with_key "${primary_key_hex}" "${val}"
    fi
}

function getkey()
{
    local salt

    salt="$1"

    echo "Enter password:" >&2
    read  -s pass

    openssl kdf \
        -keylen 32 \
        -kdfopt "pass:${pass}" \
        -kdfopt "salt:${salt}" \
        -kdfopt n:1024 \
        -kdfopt r:8 \
        -kdfopt p:16 \
        -kdfopt maxmem_bytes:10485760 \
        SCRYPT  \
        | sed 's/://g'
}

function encrypt()
{
    local salt value_hex

    salt="$1"
    shift
    value_hex="$1"

    #echo "Salt: ${salt}" >&2

    local key="$(getkey "${salt}")"

    encrypt_using_key "${key}" "${value_hex}"
}

function mk_one_line()
{
    sed -n 'H;${x;s/\n//g;p}'
}

function encrypt_using_key()
{

    local key="$1"
    shift
    local value_hex="$1"

    local iv data hmac


    tmp="${#key}"
    if [[ "${tmp}" -ne 64 ]]; then
        echo "Key too short, length ${#key}" >&2
        return
    fi
    #echo "KEY: ${key}" >&2
    iv="$(openssl rand -hex 16 )"
    #echo "IV: ${iv}" >&2
    data="$(xxd -r -p <<< "${value_hex}" | openssl enc -a -e -aes-256-ctr -nopad -K "${key}" -iv "${iv}" | mk_one_line)"
    #echo "data: ${data}" >&2
    hmac="$(openssl mac -digest SHA256 -macopt "hexkey:${key}" HMAC <<< "${data}")"
    #echo "MAC: ${hmac}" >&2

    echo "$(xxd -r -p <<< "${iv}${hmac}" | base64 | mk_one_line)${data}"
}

function encrypt_entry_with_key()
{
    local label primary_key_hex value_hex
    label="$1"
    shift
    primary_key_hex="$1"
    shift
    value_hex="$(xxd -p <<< "${*}")"

    cipher_text=$(encrypt_using_key "${primary_key_hex}"  "${value_hex}")

    echo "${label}::${cipher_text}"
}

function encrypt_entry()
{
    local salt label value_hex
    salt="$1"
    shift
    label="$1"
    shift
    value_hex="$(xxd -p <<< "${*}")"

    cipher_text=$(encrypt "${salt}" "${value_hex}")

    echo "${label}::${cipher_text}"
}


function decrypt_using_key()
{
    local key="$1"
    shift
    local data="$*"

    data="$(base64 -d <<< "${data:0:64}" | xxd -p | mk_one_line)${data:64}"

    #parse the data into constituents:
    local iv="${data:0:32}"
    local data_hmac="${data:32:64}"
    local data="${data:96}"

    local hmac="$(openssl mac -digest SHA256 -macopt "hexkey:${key}" HMAC <<< "${data}")"

    if [[ "${hmac,,*}"  == "${data_hmac}" ]]; then
        #echo "Invalid key provided for this entry."
    #else
        openssl enc -d -aes-256-ctr -nopad -a  -K "${key}" -iv "${iv}" <<< "${data}"
    fi
}

function decrypt_entry_with_key()
{
    local key="$1"
    shift
    local entry="$1"


    #trim the label:
    local label="${entry/::*/}"
    local cipher_text="${entry/*::/}"

    plain_text="$(decrypt_using_key "${key}" "${cipher_text}")"

    if [[ -z "${plain_text}" ]]; then
        echo "Invalid key provided for this entry."
    else
        echo "${plain_text}"
    fi
}

function decrypt_entry()
{

    local salt="$1"
    shift
    local entry="$1"

    local key="$(getkey "${salt}")"

    #trim the label:
    local label="${entry/::*/}"
    local cipher_text="${entry/*::/}"

    decrypt_using_key "${key}" "${cipher_text}"
}

function retrieve_pkey()
{
    local file="$1"

    local first_line="$(sed -n '1{p;q}' "${file}")"

    retrieve_pkey_from_line  "${first_line}"
}

function retrieve_pkey_from_line()
{
    local line="${1}"

    local salt="${line:0:32}"
    local entry="${line:32}"

    decrypt_entry "${salt}" "${entry}" | xxd -p  | mk_one_line
}

function list_entries()
{
    sed '1d;s/^\(.\+\)::.*$/\1/' "${notebook_file}"
}

case "${mode}" in
    s )
        ;&
    store )
        store
            ;;
    r )
        ;&
    retrieve )
        retrieve
        ;;
    cpw )
        ;&
    change_password )
        change_password
        ;;
    del )
        ;&
    rm )
        delete_entry "${label}" "${notebook_file}"
        ;;

    l )
        ;&
    list )
        list_entries
        ;;
    * )
        usage
        ;;
esac
