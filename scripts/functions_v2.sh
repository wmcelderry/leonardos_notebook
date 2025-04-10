source "${script_dir}/errorcodes_v2.sh"

function list_entries_v2()
{
    local file="${1}"
    shift

    if [[ ! -f "${file}" ]] ; then
   	 echo "File does not exist: ${file}" >&2
	 return  ${E_NO_FILE}
    fi

    pkey_hex="$(get_primary_key_v2 "${file}")"

    for entry in $(sed -n '5,$p' "${file}") 
    do
        cipher_b64="${entry##*::}"

        if [[ -n "${cipher_b64}" ]] ; then
            double_decrypt_string "${pkey_hex}" "${cipher_b64}"  | from_hex | sed 's/\(.*\)::.*/\1/g'
        fi
    done
}

function delete_entry_v2()
{
    local file="$1"
    shift
    local label="$1"

    if [[ ! -f "${file}" ]] ; then
   	 echo "File does not exist: ${file}" >&2
	 return  ${E_NO_FILE}
    fi

    local mac_b64="$(get_uid "${file}" "${label}" )"

    sed -i "/^$(echo -n ${mac_b64} | sed 's/\//\\\//g' )::/d" ${file}
}



function change_password_v2()
{
    local file="${1}"


    #Header format:
	    #Version (2.0)
	    #salt (b64)
	    #encrypted pkey
	    #fileheader (dates)
    #should update file header?)

    if [[ ! -f "${file}" ]] ; then
   	 echo "File does not exist: ${file}" >&2
	 return  ${E_NO_FILE}
    fi

    destroy_keyring_v2
    echo "Unlocking the notebook's key material, enter current password:" >&2
    local primary_key_hex="$(retrieve_pkey_v2 "${file}")"

    if [[ -z "${primary_key_hex}" ]] ; then
        echo "Failed to unlock the key." >&2
        return
    fi

    echo "Enter new password for future operation:" >&2
    local enc_header="$(encryption_header "${primary_key_hex}")"

    # confirm the password to ensure it can be unlocked!
    destroy_keyring_v2
    echo "Re-enter the new password to confirm correct spelling!" >&2
    local conf_pkey="$(retrieve_pkey_from_enc_header "${enc_header}")"

    if [[ "${conf_pkey,,*}" != "${primary_key_hex,,*}" ]] ; then
        echo "New passwords do not match!" >&2
        destroy_keyring_v2
    else
	salt_line="$(echo "${enc_header}" | sed -n '1{p;q}')"
	pkey_line="$(echo "${enc_header}" | sed -n '2p')"
	#replace lines 2 and 3.
	sed -i "${file}"  \
		-e "$(printf "2{i ${salt_line}\n;d}")"\
		-e "$(printf "3{i ${pkey_line}\n;d}")"
    fi
}



function destroy_keyring_v2()
{
    keyctl unlink "%:${keyring_name}" @u
}

function retrieve_v2()
{
    local file="$1"
    shift
    local label="$1"

    if [[ ! -f "${file}" ]] ; then
   	 echo "File does not exist: ${file}" >&2
	 return  ${E_NO_FILE}
    fi

    uid="$(get_uid "${file}" "${label}")"

    local response="Entry not found: ${label}"

    if [[ -n "${uid}" ]] ; then
        response="$(lookup_record "${file}" "${uid}")"
    fi

    if [[ -n "${response}" ]] ; then
        echo "${response#*::}"
    else
        echo "--- No entry found: ${label}" >&2
    fi
}

function destroy_keyring_v2()
{
    keyctl unlink "%:${keyring_name_v2}" @u
}

#To decide:
# -- rekey date on a per entry or a per file basis?
#   ? different types of rekey?
    #   change the entry key(s)
    #   change the primary key
    #       -- NB cannot have history of keys or rekeying a little less useful (can continue to break a constant key)
    #   change the password on the external service

# V2 File format:
    # <Version header>
    # <enc header>
    # <file header>
    # [ <entry>
    #   ...
    #   <entry> ]


#Version header:
#  "2.0"

#NB: PDK = password derived key, using PBKDF2.

# Encryption header
    # PBKDF2 salt [fixed - 16]
    # b64( HMAC, pkIV ) b64( enc( PDK, pkIV, pkey ) ) [fixed]

#File header:
    # enc( pkey, fhIV, <all following fields>) [fixed = ]
        # date of next (recommended) update of the primary key (pkey) [fixed]
        # date of next (recommended) update of the entry keys (ekey[]) [fixed]

#MAC header:
    # HMAC (PDK, <version header>, <encryption header>, <file header>) [fixed]


#V2 entry format:
#'entry_ID' :: enkMAC,enkIV,enc(pkey,enkIV,enkey) [fixed]
#               enMAC,enIV,env(enkey,enIV,#entry_label|entry_label|entry_user_data)
#<uid> "::"
#       ekMAC,ekIV,enc(pkey,ekIV,ekey) [fixed]
#       eMAC,eIV,enc(ekey,eIV,[
#               last_rekey_date
#               suggested_pw_ch_date
#               pw])




#  NB: 'rekey' meaning to decrypt all fields encrypted by a key, generate a new key and IV then re-encrypt.
