#!/bin/bash


# This file defines the interface used by 'note.sh' (the main entrypoint to this system.
# This should make it easier to move to v2.


source  "${script_dir}/backend_v1.sh"
source  "${script_dir}/functions_v1.sh"

#backend interface but used directly from note.sh
function store()
{
	#${label} is the label to store under
	#${value} is the value to store.
	store_v1
}

#functions:


function retrieve()
{
	#${label} is the label to retrieve
	retrieve_v1
}

function change_password()
{
	#no params.
	change_password_v1
}

function delete_entry()
{
	local label="${1}"
	local notebook_file="${2}"

        #${label} is the label to delete.
	#${notebook_file} is the file to delete from.

	delete_entry_v1 "${label}" "${notebook_file}"
}


function destroy_keyring()
{
	#no params.
	destroy_keyring_v1
}

function list_entries()
{
	#no params.
	list_entries_v1
}

function migrate_v1_v2()
{
	#pass it on.
	echo no-op > /dev/null
}
