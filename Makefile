CLANG := clang-18
CLANGXX := $(subst clang,clang++,$(CLANG))
LD := $(subst clang,ld.lld,$(CLANG))
OBJCOPY := $(subst clang,llvm-objcopy,$(CLANG))

MUSL := $(realpath deps/musl)
BUILTINS := $(realpath deps/builtins)
LIBCXX := $(realpath deps/libcxx)

MUSL_TARGET := $(MUSL)/release/include/stddef.h
BUILTINS_TARGET := $(BUILTINS)/build/libcompiler-rt.a
LIBCXX_TARGET := $(LIBCXX)/release/include/c++/v1/vector

DEBUG := false

BASE_CFLAGS := --target=riscv64 -march=rv64imc_zba_zbb_zbc_zbs \
	-Os \
	-fdata-sections -ffunction-sections -fvisibility=hidden

CFLAGS := -g \
  -Wall -Werror \
  -Wno-unused-function \
  -nostdinc \
  -isystem $(MUSL)/release/include \
  $(BASE_CFLAGS)

CXXFLAGS := -g \
  -Wall -Werror \
  -std=c++20 \
  -D_GNU_SOURCE \
  -nostdinc -nostdinc++ \
  -isystem $(LIBCXX)/release/include/c++/v1 \
  -isystem $(MUSL)/release/include \
  -I deps/bitcoin/src \
  -DDISABLE_OPTIMIZED_SHA256 \
  $(BASE_CFLAGS)
ifneq (true,$(DEBUG))
	CXXFLAGS += -DNO_DEBUG_INFO
endif

LDFLAGS := --gc-sections --static \
  --nostdlib --sysroot $(MUSL)/release \
  -L$(MUSL)/release/lib -L$(BUILTINS)/build \
  -lc -lgcc -lcompiler-rt \
  -L$(LIBCXX)/release/lib \
  -lc++ -lc++abi -lunwind

all: build/bitcoin_vm build/bitcoin_vm_stripped

BITCOIN_LIBS := interpreter.o sha256.o jsonlite.o script.o hash.o pubkey.o \
	secp256k1.o precomputed_ecmult.o uint256.o strencodings.o sha1.o ripemd160.o \
	hex_base.o transaction.o

build/bitcoin_vm_stripped: build/bitcoin_vm
	$(OBJCOPY) --strip-all $< $@

build/bitcoin_vm: build/main.o $(foreach o,$(BITCOIN_LIBS),build/$(o)) $(BUILTINS_TARGET)
	$(LD) $< $(foreach o,$(BITCOIN_LIBS),build/$(o)) -o $@ $(LDFLAGS) --Map=$@_link_map.txt

build/main.o: main.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS) -I deps/jsonlite/amalgamated/jsonlite

build/interpreter.o: deps/bitcoin/src/script/interpreter.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/sha256.o: deps/bitcoin/src/crypto/sha256.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS) -I build

build/jsonlite.o: deps/jsonlite/amalgamated/jsonlite/jsonlite.c $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANG) -c $< -o $@ $(CFLAGS) -I deps/jsonlite/amalgamated/jsonlite

build/script.o: deps/bitcoin/src/script/script.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/hash.o: deps/bitcoin/src/hash.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/pubkey.o: deps/bitcoin/src/pubkey.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS) -I deps/bitcoin/src/secp256k1/include

build/secp256k1.o: deps/bitcoin/src/secp256k1/src/secp256k1.c $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANG) -c $< \
		-o $@ \
		$(CFLAGS) \
		-DENABLE_MODULE_EXTRAKEYS \
		-DENABLE_MODULE_SCHNORRSIG \
		-DECMULT_WINDOW_SIZE=6 \
		-I deps/bitcoin/src/secp256k1/include

build/precomputed_ecmult.o: deps/bitcoin/src/secp256k1/src/precomputed_ecmult.c $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANG) -c $< \
		-o $@ \
		$(CFLAGS) \
		-DENABLE_MODULE_EXTRAKEYS \
		-DENABLE_MODULE_SCHNORRSIG \
		-DECMULT_WINDOW_SIZE=6 \
		-I deps/bitcoin/src/secp256k1/include

build/uint256.o: deps/bitcoin/src/uint256.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/strencodings.o: deps/bitcoin/src/util/strencodings.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/sha1.o: deps/bitcoin/src/crypto/sha1.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/ripemd160.o: deps/bitcoin/src/crypto/ripemd160.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/hex_base.o: deps/bitcoin/src/crypto/hex_base.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/transaction.o: deps/bitcoin/src/primitives/transaction.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

MUSL_CFLAGS := $(BASE_CFLAGS) -DPAGE_SIZE=4096
ifneq (true,$(DEBUG))
	MUSL_CFLAGS += -DCKB_MUSL_DUMMIFY_PRINTF
endif

$(MUSL_TARGET):
	cd $(MUSL) && \
		CLANG=$(CLANG) \
			BASE_CFLAGS="$(MUSL_CFLAGS)" \
			./ckb/build.sh

BUILTINS_CFLAGS := --target=riscv64  -march=rv64imc_zba_zbb_zbc_zbs -mabi=lp64 
BUILTINS_CFLAGS += -nostdinc -I ../musl/release/include
BUILTINS_CFLAGS += -Os
BUILTINS_CFLAGS += -fdata-sections -ffunction-sections -fno-builtin -fvisibility=hidden -fomit-frame-pointer
BUILTINS_CFLAGS += -I compiler-rt/lib/builtins
BUILTINS_CFLAGS += -DVISIBILITY_HIDDEN -DCOMPILER_RT_HAS_FLOAT16

$(BUILTINS_TARGET): $(MUSL_TARGET)
	cd $(BUILTINS) && \
		make CC=$(CLANG) \
			AR=$(subst clang,llvm-ar,$(CLANG)) \
			CFLAGS="$(BUILTINS_CFLAGS)"

LLVM_CMAKE_OPTIONS := -DCMAKE_BUILD_TYPE=MinSizeRel
LLVM_CMAKE_OPTIONS += -DLIBCXX_ENABLE_WIDE_CHARACTERS=OFF -DLIBCXX_ENABLE_UNICODE=OFF -DLIBCXX_ENABLE_RANDOM_DEVICE=OFF
LLVM_CMAKE_OPTIONS += -DLIBCXXABI_SILENT_TERMINATE=ON

$(LIBCXX_TARGET): $(MUSL_TARGET)
	cd $(LIBCXX) && \
		CLANG=$(CLANG) \
			BASE_CFLAGS="$(BASE_CFLAGS)" \
			MUSL=$(MUSL)/release \
			LLVM_VERSION="18.1.8" \
			LLVM_PATCH="$(realpath llvm_patch)" \
			LLVM_CMAKE_OPTIONS="$(LLVM_CMAKE_OPTIONS)" \
		  ./build.sh
	touch $@

clean:
	rm -rf build/bitcoin_vm build/bitcoin_vm_stripped build/*.o build/*.txt
	cd $(MUSL) && make clean && rm -rf release
	cd $(BUILTINS) && make clean
	cd $(LIBCXX) && rm -rf release

.PHONY: clean all
