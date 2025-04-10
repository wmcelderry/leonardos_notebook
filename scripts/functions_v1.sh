
function list_entries_v1()
{
    sed '1d;s/^\(.\+\)::.*$/\1/' "${notebook_file_v1}"
}

function delete_entry_v1()
{
    local label notebook_file_v1

    label="$1"
    notebook_file_v1="$2"

    sed -i "/^${label}::/d" "${notebook_file_v1}"
}



function change_password_v1()
{
    local file="${notebook_file_v1}"

    destroy_keyring_v1
    echo "Unlocking the key material, enter current password:" >&2
    local primary_key_hex="$(retrieve_pkey_v1 "${file}")"

    if [[ -z "${primary_key_hex}" ]] ; then
        echo "Failed to unlock the key." >&2
        return
    fi

    destroy_keyring_v1
    echo "Enter new password for future operation:" >&2
    local password_line="$(gen_password_line "${primary_key_hex}")"

    # confirm the password to ensure it can be unlocked!
    destroy_keyring_v1
    echo "Re-enter the new password to confirm correct spelling!" >&2
    local conf_pkey="$(retrieve_pkey_from_line_v1 "${password_line}")"

    if [[ "${conf_pkey,,*}" != "${primary_key_hex,,*}" ]] ; then
        echo "New passwords do not match!" >&2
        destroy_keyring_v1
    else
        sed -i "1s!.*!${password_line}!g" "${file}"
    fi
}



function destroy_keyring_v1()
{
    keyctl unlink "%:${keyring_name_v1}" @u
}

function retrieve_v1()
{
    local entry="$(get_entry_v1 "${label}")"
    local primary_key_hex="$(retrieve_pkey_v1 "${notebook_file_v1}")"

    if [[ -z "${primary_key_hex}" ]] ; then
        echo "Incorrect key for decrypting." >&2
        return
    fi

    if [[ -z "${entry}" ]] ; then
        echo "Cannot find entry for '${label}'" >&2
    else
        decrypt_entry_with_key_v1 "${primary_key_hex}" "${entry}"
    fi
}
