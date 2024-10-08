#!/bin/bash

base_dir="$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")" )"

function usage()
{
    cat <<-EOF
${BASH_SOURCE[0]} <mode> <label> [<value...>]

  mode is one of:
    "store" | "s"     <label> <value...>
    "retrieve" | "r"  <label>
    "paste" | "p"     <label>
    "totp" | "t"      <label>
    "del" | "rm"      <label>
    "change_password"|"cpw"
    "list" | "l"
    "clear" | "c"

  store     adds a new entry
  retrieve  recovers an entry
  paste     recovers an entry to the clipboard.
  totp      recovers an entry, uses it as input for oathtool totp and puts that on the clipboard.
  rm        removes an entry
  change_password
            allows changing the password
  list      lists the entries
  clear     clear any cached key from the keyring
EOF
}


mode="$1"
shift
label="$1"
shift
value="$*"

notebook_file="${base_dir}/data/my_primary_notebook"
keyring_name="leonardo"
key_prefix="leo"
key_name="primary"
key_period=300



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

    destroy_keyring
    echo "Unlocking the key material, enter current password:" >&2
    local primary_key_hex="$(retrieve_pkey "${file}")"

    if [[ -z "${primary_key_hex}" ]] ; then
        echo "Failed to unlock the key." >&2
        return
    fi

    destroy_keyring
    echo "Enter new password for future operation:" >&2
    local password_line="$(gen_password_line "${primary_key_hex}")"

    # confirm the password to ensure it can be unlocked!
    destroy_keyring
    echo "Re-enter the new password to confirm correct spelling!" >&2
    local conf_pkey="$(retrieve_pkey_from_line "${password_line}")"

    if [[ "${conf_pkey,,*}" != "${primary_key_hex,,*}" ]] ; then
        echo "New passwords do not match!" >&2
        destroy_keyring
    else
        sed -i "1s!.*!${password_line}!g" "${file}"
    fi
}


function gen_password_line()
{
    local primary_key_hex="$1"

    #put the KDF salt and primary key in the notebook_file.
    local salt="$(openssl rand -hex 16)"

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
            echo "Incorrect key for encrypting." >&2
            return
        fi
    else
        primary_key_hex="$(create_notebook_file "${notebook_file}")"
    fi

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
    local entry="$(get_entry "${label}")"
    local primary_key_hex="$(retrieve_pkey "${notebook_file}")"

    if [[ -z "${primary_key_hex}" ]] ; then
        echo "Incorrect key for decrypting." >&2
        return
    fi

    if [[ -z "${entry}" ]] ; then
        echo "Cannot find entry for '${label}'" >&2
    else
        decrypt_entry_with_key "${primary_key_hex}" "${entry}"
    fi
}

function destroy_keyring()
{
    keyctl unlink "%:${keyring_name}" @u
}

function getDerivedKey()
{
    local salt="$1"

    echo "Enter password:" >&2
    read  -s pass

    local dkey="$(openssl kdf \
        -keylen 32 \
        -kdfopt "pass:${pass}" \
        -kdfopt "salt:${salt}" \
        -kdfopt n:1024 \
        -kdfopt r:8 \
        -kdfopt p:16 \
        -kdfopt maxmem_bytes:10485760 \
        SCRYPT  \
        | sed 's/://g')"

    echo "${dkey}"
}

function getCachedKey()
{
    local key_id="$(keyctl search "%:${keyring_name}" user "${key_prefix}:${key_name}" 2>/dev/null)"

    if [[ -n "${key_id}" ]] ; then
        keyctl timeout "${key_id}" "${key_period}"
        keyctl pipe "${key_id}" | xxd -p  | mk_one_line
    fi
}

function addKeyToKeyring()
{
    local key="$1"

    local keyring_id="$(keyctl search @u keyring "${keyring_name}" 2>/dev/null)"

    if [[ -z "${keyring_id}" ]]  ; then
        keyring_id="$(keyctl newring "${keyring_name}" @u)"
    fi

    local key_id="$(xxd -r -p <<< "${key}" | keyctl padd user "${key_prefix}:${key_name}" "${keyring_id}")"
    keyctl timeout "${key_id}" "${key_period}"
}

function encrypt()
{
    local salt value_hex

    salt="$1"
    shift
    value_hex="$1"

    local key="$(getDerivedKey "${salt}")"

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

    iv="$(openssl rand -hex 16 )"

    data="$(xxd -r -p <<< "${value_hex}" | openssl enc -a -e -aes-256-ctr -nopad -K "${key}" -iv "${iv}" | mk_one_line)"
    hmac="$(openssl mac -digest SHA256 -macopt "hexkey:${key}" HMAC <<< "${data}")"

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
        echo "Invalid key provided for this entry." >& 2
    else
        echo "${plain_text}"
    fi
}

function decrypt_entry()
{

    local salt="$1"
    shift
    local entry="$1"


    #trim the label:
    local label="${entry/::*/}"
    local cipher_text="${entry/*::/}"

    local limit=3
    for((try=0;try < ${limit}; try++))
    do
        local key="$(getDerivedKey "${salt}")"
        local plaintext="$(decrypt_using_key "${key}" "${cipher_text}")"

        if [[ -n "${plaintext}" ]] ; then
            echo -n "${plaintext}"
            break
        else
            echo -n "Attempt $((try+1)) of ${limit}: Incorrect passphrase" >&2

            if [[ "$((try+1))" -lt "${limit}" ]]; then
                echo ", please try again." >&2
            else
                echo ", retry limit reached." >&2
            fi
        fi
    done
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

    local pkey="$(getCachedKey)"

    if [[ -n "${pkey}" ]] ; then
        echo "${pkey}"
        return
    fi

    local pkey="$(decrypt_entry "${salt}" "${entry}" | xxd -p  | mk_one_line)"

    if [[ -z "${pkey}" ]] ; then
        return
    fi

    addKeyToKeyring "${pkey}"
    echo "${pkey}"
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

    p )
        ;&
    paste )
        retrieve "$@" | xclip -i -selection clipboard -l 1 -quiet
        ;;

    t )
        ;&
    totp )
        oathtool --totp --base32 "$(retrieve "$@" )" | xclip -i -selection clipboard -l 1 -quiet
        ;;
    c )
        ;&
    clear )
        destroy_keyring
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
