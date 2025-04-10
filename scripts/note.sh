#!/bin/bash


script_dir="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
base_dir="$(dirname "${script_dir}" )"

source  "${script_dir}/interface.sh"
source  "${script_dir}/utils.sh"



function number()
{
    sed '=' | sed 'N;s/\n/ /g'
}

function usage()
{
    cat <<-EOF
${BASH_SOURCE[0]} <action> [<label>] [<prefix> [<value...>] ]

  action is one of:
    "store" | "s"               <label> [<prefix> [<value...>] ]
    "gen_64" | "g64"            <label> [<prefix>]
    "gen_words" | "gw"          <label> [<prefix>]
    "retrieve" | "r"            <label> [<prefix>]
    "paste" | "p"               <label> [<prefix>]
    "paste_prim" | "pp"         <label> [<prefix>]
    "totp" | "t"                <label> [<prefix>]
    "del" | "rm"                <label> [<prefix>]
    "change_password"|"cpw"     <prefix>
    "list" | "l" | "ls"         <prefix>
    "clear" | "c"               <prefix>

  store       adds a new entry, if there is no value it is taken from stdin.
  gen_b64     generate a random base64 key and store it
  gen_words   generate a random word key and store it
  retrieve    recovers an entry
  paste       recovers an entry to the clipboard.
  paste_prim  recovers an entry to the primary selection.
  totp        recovers an entry, uses it as input for oathtool totp and puts that on the clipboard.
  rm        removes an entry
  change_password
            allows changing the password
  list      lists the entries
  clear     clear any cached key from the keyring
EOF
}


action="$1"
shift

case "${action}" in
    c | clear )
        prefix="$1"
        shift
        ;;
    l | ls | list )
        prefix="$1"
        shift
        ;;
    cpw | change_password )
        prefix="$1"
        shift
        ;;
    s | store )
        label="$1"
        shift
        prefix="$1"
        shift
        value="$*"
        ;;
    *)
        label="$1"
        shift
        prefix="$1"
        ;;
esac

notebook_file_v1="${base_dir}/data/my_primary_notebook"
notebook_file_v2="${base_dir}/data/${prefix:+${prefix}-}notebook_v2.enc"

keyring_name_v1="leonardo_legacy"
keyring_name_v2="leonardo-${prefix}"

#All current versions use these settings:
key_prefix="leo"
key_name="primary"
key_period=300


case "${action}" in
    r )
        ;&
    retrieve )
        retrieve_v2 "${notebook_file_v2}" "${label}"
        ;;
    s )
        ;&
    store )
        if [[ ! -f "${notebook_file_v2}" ]] ; then
            echo "Creating a new notebook: ${notebook_file_v2}" >&2
            create_notebook_file_v2 "${notebook_file_v2}"
        fi
        position="$( (
            list_entries_v2 "${notebook_file_v2}" |  grep -v "\<${label}\>"
            echo "${label}"
            ) | sort | number | grep "\<${label}\>" | cut -d ' ' -f 1)"
        #echo insert at "${position}" >&2
        add_entry "${notebook_file_v2}" "${label}" "${value}"
        ;;
    del )
        ;&
    rm )
        delete_entry_v2 "${notebook_file_v2}" "${label}"
        ;;
    pop )
        if retrieve_v2 "${notebook_file_v2}" "${label}" ; then
            delete_entry_v2 "${notebook_file_v2}" "${label}"
        fi
        ;;
    del_file )
        ;&
    rm_file )
        rm "${notebook_file_v2}"
        ;;
    c )
        ;&
    clear )
        destroy_keyring_v2
        ;;

    cpw )
        ;&
    change_password )
        change_password_v2 "${notebook_file_v2}"
        ;;

    g64 )
        ;&
    gen_64 )
        value="$(generate_b64_pass)"
        add_entry "${notebook_file_v2}" "${label}" "${value}"
        ;;
    gw )
	;&
    gen_words )
        value="$(generate_words_pass)"
        add_entry "${notebook_file_v2}" "${label}" "${value}"
	;;

    pp )
        ;&
    paste_prim )
        retrieve_v2 "${notebook_file_v2}" "${label}" | xclip -i -selection primary -l 1 -quiet
        ;;
    p )
        ;&
    paste )
        retrieve_v2 "${notebook_file_v2}" "${label}" | xclip -i -selection clipboard -l 1 -quiet
        ;;

    t )
        ;&
    totp )
        oathtool --totp --base32 "$(retrieve_v2 "${notebook_file_v2}" "${label}" "$@" )" | xclip -i -selection clipboard -l 1 -quiet
        ;;
    l )
        ;&
    ls )
        ;&
    list )
        list_entries_v2 "${notebook_file_v2}" # | \
            #sort -k 2
        ;;

    # version specified:
    migrate )
        migrate_v1_v2
        ;;

    * )
        usage
        ;;
esac
