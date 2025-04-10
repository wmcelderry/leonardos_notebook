keyring_name=leo_dev
key_prefix=leo_dev_pre
key_name=dev_key

pkey_refresh_period=365
ekey_refresh_period=30
password_refresh_period=180

key_period=5

source "${script_dir}/errorcodes_v2.sh"

function version_header()
{
    echo "2.0"
}

function encryption_header()
{
    local pkey_hex="${1}"

    local salt_hex="$(mk_salt)"
    local primary_key_hex="${pkey_hex}"

    echo  "${salt_hex}" | from_hex | base64 | mk_one_line
    echo "$(encrypt_with_pdk "${salt_hex}" "${primary_key_hex}")"
    #addKeyToKeyring "${primary_key_hex}" #do not do this on creation to force the user to type their password to help embed it in their mind.
}

function file_header()
{
    local pkey_hex="${1}"

    local next_pkey_refresh="$(printf %016x $(date -d "+${pkey_refresh_period} days" +%s))"
    local next_ekey_refresh="$(printf %016x $(date -d "+${ekey_refresh_period} days" +%s))"

    echo "$(double_encrypt_string "${pkey_hex}" "${next_pkey_refresh}${next_ekey_refresh}")"
}

function create_notebook_file_v2()
{
    local file="${1}"
    local primary_key_hex="$(mk_key)"

    ( 
        version_header
    	encryption_header "${primary_key_hex}"
        file_header "${primary_key_hex}"

    ) >> "${file}"
}


function extract_enc_header()
{
    read version

    if [[ ${version} != "2.0" ]] ; then
        echo Wrong version, expect 2.0 got: ${version} >&2
        return $E_WRONG_VERSION;
    fi

    read salt_b64
    read enc_header_b64

    echo "$(echo ${salt_b64} | base64 -d | to_hex | mk_one_line)"
    echo "${enc_header_b64}"

    enc_header_hex="$(echo ${enc_header_b64} | base64 -d | to_hex | mk_one_line)"
}


function retrieve_pkey_v2()
{
    local file="${1}"
	#extract the primary key from the cache or the file.
	enc_header_b64="$(sed '5q' "${file}" | extract_enc_header)"
	salt_hex="$(echo "${enc_header_b64}" | sed -n '1p;q')";
	enc_pkey_b64="$(echo "${enc_header_b64}" | sed -n '2p')";

	local derived_key_hex="$(getDerivedKey "${salt_hex}")"

	decrypt_string "${derived_key_hex}" "${enc_pkey_b64}"
}

function get_primary_key_v2()
{
    local file="${1}"

    local pkey_hex="$(getCachedKey)"

    if [[ -z "${pkey_hex}" ]] ; then
        pkey_hex="$(retrieve_pkey_v2 "${file}" )"
    fi

    if [[ -n "${pkey_hex}" ]] ; then
	    echo "${pkey_hex}"
	    addKeyToKeyring "${pkey_hex}"
    fi
}


function lookup_record()
{
    local file="${1}"
    shift
    local uid="${1}"

    pkey_hex="$(get_primary_key_v2 "${file}")"

    entry="$(grep '^'"${uid}"'::' "${file}")"
    cipher_b64="${entry##*::}"

    if [[ -n "${cipher_b64}" ]] ; then
        double_decrypt_string "${pkey_hex}" "${cipher_b64}"  | from_hex
    fi
}

function get_uid()
{
    local file="${1}"
    shift
    local label="${1}"

    pkey_hex="$(get_primary_key_v2 "${file}")"

    uid="$(echo -n ${label} | hmac "${pkey_hex}" | from_hex | base64 | mk_one_line)"

    #grep -q "^${uid}" ${file} && echo ${uid}
    echo ${uid}
}



function encrypt_with_pdk()
{
    local salt_hex="$1"
    shift
    local value_hex="$1"

    local derived_key_hex="$(getDerivedKey "${salt_hex}")"
    ciphertext="$(encrypt_string "${derived_key_hex}" "${value_hex}")"
    echo ${ciphertext}
}


function getDerivedKey()
{
    local salt_hex="$1"

    echo "Enter the Notebook password:" >&2
    read  -s pass

    local dkey="$(openssl kdf \
        -keylen 32 \
        -kdfopt "pass:${pass}" \
        -kdfopt "salt:${salt_hex}" \
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
        keyctl pipe "${key_id}" | to_hex  | mk_one_line
    fi
}



function addKeyToKeyring()
{
    local key="$1"

    local keyring_id="$(keyctl search @u keyring "${keyring_name}" 2>/dev/null)"

    if [[ -z "${keyring_id}" ]]  ; then
        keyring_id="$(keyctl newring "${keyring_name}" @u)"
    fi

    local key_id="$(echo -n "${key}" | from_hex | keyctl padd user "${key_prefix}:${key_name}" "${keyring_id}")"
    keyctl timeout "${key_id}" "${key_period}"
}



function hex_to_bin()
{
    #params converted from hex to bin 
    echo -n "$*" | from_hex
}

function b64_to_bin()
{
    echo -n "$*" | base64 -d
}

function mk_key()
{
    openssl rand -hex 32
}

function mk_salt()
{
    openssl rand -hex 16
}
function mk_iv()
{
    openssl rand -hex 16
}

function aes_ctr()
{
    local key_hex="${1}"
    shift
    local iv_hex="${1}"
    shift

    openssl enc -A -a -e -aes-256-ctr -K "${key_hex}" -iv "${iv_hex}"
}

function aes_cbc()
{
    local key_hex="${1}"
    shift
    local iv_hex="${1}"
    shift
    local nopad="${1}"


    openssl enc -A -a -e -aes-256-cbc ${nopad:+-nopad} -K "${key_hex}" -iv "${iv_hex}"
}

function encrypt_string()
{
    local key_hex="$1"
    shift
    local value_hex="$1"
    shift
    local nopad="$1"


    if [[ "${#key_hex}" -ne 64 ]]; then
        echo "Key wrong lenght: length is ${#key_hex}" >&2
        return
    fi

    local iv_hex="$(mk_iv)"

    local ciphertext_b64
    ciphertext_b64="$(echo -n "${value_hex}" | from_hex | aes_cbc "${key_hex}" "${iv_hex}" "${nopad}")"

    local hmac_hex="$( ( hex_to_bin "${iv_hex}" ; b64_to_bin "${ciphertext_b64}" )  | hmac "${key_hex}" )"

    echo -n "$( echo -n "${hmac_hex}${iv_hex}" | from_hex | base64 )${ciphertext_b64}" | mk_one_line
}

function to_hex()
{
	xxd -p
}

function from_hex()
{
    xxd -r -p
}


function hmac()
{
    local key_hex="$1"

    openssl mac -digest SHA256 -macopt "hexkey:${key_hex}" HMAC
}


function decrypt_string()
{
    local key_hex="$1"
    shift
    local data_b64="$1"
    shift
    local nopad="$1"

    local data_hex="$(b64_to_bin "${data_b64}" | to_hex | mk_one_line)"

    #parse the data into constituents:
    local hmac_hex="${data_hex:0:64}"
    local iv_hex="${data_hex:64:32}"
    local data_hex="${data_hex:96}"

    #local hmac="$(openssl mac -digest SHA256 -macopt "hexkey:${key}" HMAC <<< "$(hex_to_bin "${iv}" ; hex_to_bin "${data}") " )"
    local data_hmac_hex="$( hex_to_bin "${iv_hex}${data_hex}"  | hmac "${key_hex}" )"

    if [[ "${hmac_hex,,*}"  == "${data_hmac_hex,,*}" ]]; then
        hex_to_bin "${data_hex}" | openssl enc -d -aes-256-cbc ${nopad:+-nopad} -K "${key_hex}" -iv "${iv_hex}" | to_hex | mk_one_line
    else
        echo "HMAC does not match: ${hmac_hex,,*} != ${data_hmac_hex,,*}" >&2
		return $E_INCORRECT_MAC
    fi
}

function double_encrypt_string()
{
    local pkey_hex="$1"
    shift
    local value_hex="$1"


    #generate a new key and encrypt with it, then prefix the key and encrypt with the pkey.

    local ekey_hex="$(mk_key)"
    local ecipher_b64="$(encrypt_string "${ekey_hex}" "${value_hex}")"

    #no need for padding on the second encypt - but make sure that double decrypt matches.
    encrypt_string "${pkey_hex}" "${ekey_hex}$(echo -n $ecipher_b64 | base64 -d | to_hex | mk_one_line)" "nopad"
}

function double_decrypt_string()
{
    local pkey_hex="$1"
    shift
    local ciphertext_b64="$1"


    local ecipher_hex="$(decrypt_string "${pkey_hex}" "${ciphertext_b64}" "nopad" )"

    local ekey_hex="${ecipher_hex:0:64}"
    local ecipher_b64="$( echo -n ${ecipher_hex:64} | xxd -r -p | base64 | mk_one_line)"

    decrypt_string "${ekey_hex}" "${ecipher_b64}"
}


function insert_entry()
{
    local file="$1"
    shift
    local label="$1"
    shift
    local line="$1" #4 is before the first entry that is there, 5 is after the first entry.
    shift
    local value="$1"

    local mac_b64="$(get_uid "${file}" "${label}" )"
    local pkey_hex="$(get_primary_key_v2 "${file}")"

    if [[ -z "${value}" ]] ; then
	    read -p "Enter the password to store now:" value >&2
    fi

    sed -i "/^$(echo -n ${mac_b64} | sed 's/\//\\\//g' )::/d" ${file}

    cmd="a "
    if [[ "${line}" -lt 4 ]] ; then
	    echo "ERROR: invalid position within the file given: ${line}" >&2
	    return -1
    fi

    [[ ! -f "${file}" ]] && (echo creating: ${file}; touch "${file}" )
    sed -i "${line}${cmd} ${mac_b64}::$(double_encrypt_string "${pkey_hex}" "$(echo ${label}::${value} | to_hex)")" "${file}"
}

function add_entry()
{
    local file="$1"
    shift
    local label="$1"
    shift
    local value="$1"

    line="$(( $( ( list_entries_v2 "${file}" ; echo "${label}" ) | sort | number | grep "${label}" | cut -d' ' -f 1 ) + 3 ))" # add three to account for 4 header lines!

    insert_entry "${file}" "${label}" "${line}" "${value}"
}
