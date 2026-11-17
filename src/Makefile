# O build fica no Makefile da raiz. Este arquivo so repassa os alvos.
.PHONY: all
all:
	$(MAKE) -C .. all
%:
	$(MAKE) -C .. $@
