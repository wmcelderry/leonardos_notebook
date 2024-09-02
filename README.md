# Leonardo's notebook
This is a way of storing data so only the intended reader can read it - just like Leonardo's notebook - or a password manager.

# Purpose of this repository
This repo demonstrates the basics of symmetric key encryption through using the `openssl` CLI.
It is a toy example to store encrypted notes and shows how a simple password manager can operate.

# NB: Caveat Usus - USER BEWARE!
While the algorithms used and data generated is/should be 'quite hard'\* to decrypt without the key (e.g. while at rest), the method of invoking openssl with `-K`, `-macopt hexkey:...` and `-kdfopt "pass:..."`, perhaps other commandline params too? could reveal key material to other users if used on a multi-user computer.
At best it is OK to use on a secure single user computer: the resulting cipher should be secure if an appropriately complex password has been used.
At worst there is an error in the code and all data is essentially encrypted with the same predictable key - that would mean that sharing a notebook would make the entire contents available to the recipient! (basic testing suggests this is not the case, but it has not been exhasutively tested !)

\* understatement.

# (Quick and dirty) Analysis of notebook content: Is it safe to make public?

The material stored in the notebook is of the form:
    ${label}::${IV_hex}${HMAC_hex}{aes256_ctr_encrypted_data_base64}

All of which should be pretty safe to share/useless without the corresponding key.

* label - user label to identify the encrypted row - this is the most dangerous information in the file and could accidentally reveal something that may reveal the key!
* IV 'initialisation vector' are just a very big 'number use once' - one should never really reuse them with the same key.  Technically the random selection of this number COULD cause them to be reused, but the chance is vanisihingly small.  Being a random number that cannot be reused, it doesn't betray any information about your key or the decrypted data.
* HMAC is a secure hash of data - a number derived from the key and encrypted data that has been mathematically shown does not reveal anything about the data it is derived from.
* aes256_ctr_encrypted_data_base64 is the encrypted data - totally fine to reveal this to the world, as long as the key remains secret!




# Great to hear your thoughts!
I'd love to hear from anyone if they agree or disagree with the conclusion that sharing the encrypted notebook file will not reveal any information without revealing the key used for the specific label.
I'm also interested to move it to a keyring based implementation, but haven't yet explored for a CLI - any pointers would be appreciated!



# Forgotten a password?
I can totally tell you your password, just email me... and give me all the computer resources until the end of time, plus a bit longer.  Now I write it out loud, it may be better if you don't forget your password, or only use it for information you are OK losing!


# Possible Improvement in operation?
## Avoid readable labels
To avoid having labels that could leak information, operation could be modified so that a standard label is used to encrypt the labels.  When a value needs to be looked up, the standard label would need to be decrypted and the output restricted to identify which of the ordinals/UUIDs should be decrypted to get the desired value.  Requires a double decryption instead of a single

## Avoid losing the keys?
To ensure that a key cannot be lost, you could export the raw key.


# FAQ

## 1. What's with the name 'Leonardo's Notebook'?
Leonardo Da Vinci used mirror writing in his notebook, possibly to keep his notes secret.  That's what this does.  Like his, this implementation may also be imperfect...
