
E_WRONG_VERSION=-20
E_NO_FILE=-21
E_NO_KEY=-22 # indicates that the KDF key could not be generated.
E_INCORRECT_MAC=-23 #indicates that an entry could not be correctly decrypted - perhaps because the Key is incorrect (possibly wrong KDF input, possibly tampered with) or that the data has been tampered with impacting the ability to decrypt or to correctly compare with the MAC.
