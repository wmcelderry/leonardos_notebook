#!/bin/bash


script_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
base_dir="$(dirname "${script_dir}" )"

source  "${script_dir}/functions_v1.sh"
source  "${script_dir}/backend_v1.sh"
source  "${script_dir}/utils.sh"

function usage()
{
    cat <<-EOF
${BASH_SOURCE[0]} <mode> <label> [<value...>]

  mode is one of:
    "store" | "s"     <label> [<value...>]
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
