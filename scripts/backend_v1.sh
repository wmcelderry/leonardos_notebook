function create_notebook_file_v1()
{
    local file="${1}"
    local primary_key_hex="$(openssl rand -hex 32)"

    gen_password_line_v1 "${primary_key_hex}" >> "${file}"

    echo "${primary_key_hex}"
}

function gen_password_line_v1()
{
    local primary_key_hex="$1"

    #put the KDF salt and primary key in the notebook_file.
    local salt="$(openssl rand -hex 16)"

    echo  -n "${salt}"

    #store the primary key, protected by the password
    encrypt_v1 "${salt}" "${primary_key_hex}"
}



function get_entry_v1()
{
    local label

    label="$1"
    [[ -e "${notebook_file}" ]] && sed -n "/^${label}::/{p;q}" "${notebook_file}"
}

function store_v1()
{
    local salt

    if [[ -e "${notebook_file}" ]] ; then
        delete_entry_v1 "${label}" "${notebook_file}"
        primary_key_hex="$(retrieve_pkey_v1 "${notebook_file}")"
        if [[ -z "${primary_key_hex}" ]] ; then
            echo "Incorrect key for encrypting." >&2
            return
        fi
    else
        primary_key_hex="$(create_notebook_file_v1 "${notebook_file}")"
    fi

    [[ -z "${value}" ]] && echo "Taking value from standard in now..." >&2 && value="$(cat)"
    encrypt_entry_with_key_v1 "${label}" "${primary_key_hex}" "${value}" >> "${notebook_file}"
}

function encrypt_v1()
{
    local salt value_hex

    salt="$1"
    shift
    value_hex="$1"

    local key="$(getDerivedKey_v1 "${salt}")"

    encrypt_using_key_v1 "${key}" "${value_hex}"
}


function getDerivedKey_v1()
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



function getCachedKey_v1()
{
    local key_id="$(keyctl search "%:${keyring_name}" user "${key_prefix}:${key_name}" 2>/dev/null)"

    if [[ -n "${key_id}" ]] ; then
        keyctl timeout "${key_id}" "${key_period}"
        keyctl pipe "${key_id}" | xxd -p  | mk_one_line
    fi
}



function addKeyToKeyring_v1()
{
    local key="$1"

    local keyring_id="$(keyctl search @u keyring "${keyring_name}" 2>/dev/null)"

    if [[ -z "${keyring_id}" ]]  ; then
        keyring_id="$(keyctl newring "${keyring_name}" @u)"
    fi

    local key_id="$(xxd -r -p <<< "${key}" | keyctl padd user "${key_prefix}:${key_name}" "${keyring_id}")"
    keyctl timeout "${key_id}" "${key_period}"
}



function encrypt_using_key_v1()
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

function encrypt_entry_with_key_v1()
{
    local label primary_key_hex value_hex
    label="$1"
    shift
    primary_key_hex="$1"
    shift
    value_hex="$(xxd -p <<< "${*}")"

    cipher_text=$(encrypt_using_key_v1 "${primary_key_hex}"  "${value_hex}")

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


function decrypt_using_key_v1()
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

function decrypt_entry_with_key_v1()
{
    local key="$1"
    shift
    local entry="$1"


    #trim the label:
    local label="${entry/::*/}"
    local cipher_text="${entry/*::/}"

    plain_text="$(decrypt_using_key_v1 "${key}" "${cipher_text}")"

    if [[ -z "${plain_text}" ]]; then
        echo "Invalid key provided for this entry." >& 2
    else
        echo "${plain_text}"
    fi
}

function decrypt_entry_v1()
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
        local key="$(getDerivedKey_v1 "${salt}")"
        local plaintext="$(decrypt_using_key_v1 "${key}" "${cipher_text}")"

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

function retrieve_pkey_v1()
{
    local file="$1"

    local first_line="$(sed -n '1{p;q}' "${file}")"

    retrieve_pkey_from_line_v1  "${first_line}"
}

function retrieve_pkey_from_line_v1()
{
    local line="${1}"

    local salt="${line:0:32}"
    local entry="${line:32}"

    local pkey="$(getCachedKey_v1)"

    if [[ -n "${pkey}" ]] ; then
        echo "${pkey}"
        return
    fi

    local pkey="$(decrypt_entry_v1 "${salt}" "${entry}" | xxd -p  | mk_one_line)"

    if [[ -z "${pkey}" ]] ; then
        return
    fi

    addKeyToKeyring_v1 "${pkey}"
    echo "${pkey}"
}

