LUA ?= lua5.4
CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -fPIC
LUA_CFLAGS := $(shell pkg-config --cflags $(LUA))
LUA_LIBS := $(shell pkg-config --libs $(LUA))

TARGET = ../r_data_c.so

all: $(TARGET)

$(TARGET): r_data_c.c
	$(CC) $(CFLAGS) $(LUA_CFLAGS) -shared -o $@ $< $(LUA_LIBS)

clean:
	rm -f $(TARGET)

.PHONY: all clean
