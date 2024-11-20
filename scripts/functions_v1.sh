
function list_entries()
{
    sed '1d;s/^\(.\+\)::.*$/\1/' "${notebook_file}"
}

function delete_entry()
{
    local label notebook_file

    label="$1"
    notebook_file="$2"

    sed -i "/^${label}::/d" "${notebook_file}"
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



function destroy_keyring()
{
    keyctl unlink "%:${keyring_name}" @u
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
