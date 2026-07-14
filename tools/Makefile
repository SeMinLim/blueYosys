CC ?= cc
CFLAGS ?= -O2 -std=c11 -Wall -Wextra -Wpedantic
CPPFLAGS ?= -D_POSIX_C_SOURCE=200809L

BIN_DIR := bin
TARGET := $(BIN_DIR)/replacetoken

.PHONY: all clean

all: $(TARGET)

$(TARGET): replacetoken.c | $(BIN_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $<

$(BIN_DIR):
	mkdir -p $@

clean:
	rm -rf $(BIN_DIR)
