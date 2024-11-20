
function mk_one_line()
{
    sed -n 'H;${x;s/\n//g;p}'
}

function generate_b64_pass()
{
	while read -p "Enter a password: " -i $(openssl rand 9 | base64)  -e p >&2 ;
	do
		if [[ -n "${p}" ]] ; then
			break
		fi
	done

	echo ${p}
}

