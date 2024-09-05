CLANG := clang-18
CLANGXX := $(subst clang,clang++,$(CLANG))
LD := $(subst clang,ld.lld,$(CLANG))
OBJCOPY := $(subst clang,llvm-objcopy,$(CLANG))

MUSL := $(realpath deps/musl)
BUILTINS := $(realpath deps/builtins)
LIBCXX := $(realpath deps/libcxx)
ATOMICS := $(realpath deps/dummy-atomics)

MUSL_TARGET := $(MUSL)/release/include/stddef.h
BUILTINS_TARGET := $(BUILTINS)/build/libcompiler-rt.a
LIBCXX_TARGET := $(LIBCXX)/release/include/c++/v1/vector
ATOMICS_TARGET := $(ATOMICS)/libdummyatomics.a

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
  -lc++ -lc++abi -lunwind \
  -L$(ATOMICS) \
  -ldummyatomics

all: build/bitcoin_vm build/bitcoin_vm_stripped

BITCOIN_LIBS := interpreter.o sha256.o jsonlite.o script.o hash.o pubkey.o \
	secp256k1.o precomputed_ecmult.o uint256.o strencodings.o sha1.o ripemd160.o \
	hex_base.o transaction.o

# Following are all direct/indirect dependencies of core_write.cpp source file
BITCOIN_LIBS += core_write.o cleanse.o key_io.o solver.o addresstype.o lockedpool.o \
	descriptor.o key.o random.o chacha20.o base58.o sha512.o hmac_sha512.o \
	bech32.o signingprovider.o parsing.o check.o randomenv.o clientversion.o \
	bip32.o outputtype.o logging.o time.o miniscript.o threadnames.o fs.o \
	syserror.o univalue.o univalue_read.o precomputed_ecmult_gen.o \
	chainparams.o kernel_chainparams.o args.o chaintype.o univalue_get.o \
	fs_helpers.o merkle.o univalue_write.o settings.o deploymentinfo.o block.o \
	chainparamsbase.o script_error.o

build/bitcoin_vm_stripped: build/bitcoin_vm
	$(OBJCOPY) --strip-all $< $@

build/bitcoin_vm: build/main.o $(foreach o,$(BITCOIN_LIBS),build/$(o)) $(BUILTINS_TARGET) $(ATOMICS_TARGET)
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

build/core_write.o: deps/bitcoin/src/core_write.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS) -I build -I deps/bitcoin/src/univalue/include

build/cleanse.o: deps/bitcoin/src/support/cleanse.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/key_io.o: deps/bitcoin/src/key_io.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/solver.o: deps/bitcoin/src/script/solver.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/addresstype.o: deps/bitcoin/src/addresstype.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/lockedpool.o: deps/bitcoin/src/support/lockedpool.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/descriptor.o: deps/bitcoin/src/script/descriptor.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/key.o: deps/bitcoin/src/key.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS) -I deps/bitcoin/src/secp256k1/include

build/random.o: deps/bitcoin/src/random.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS) -I build

build/chacha20.o: deps/bitcoin/src/crypto/chacha20.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/base58.o: deps/bitcoin/src/base58.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/sha512.o: deps/bitcoin/src/crypto/sha512.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/hmac_sha512.o: deps/bitcoin/src/crypto/hmac_sha512.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/bech32.o: deps/bitcoin/src/bech32.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/signingprovider.o: deps/bitcoin/src/script/signingprovider.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/parsing.o: deps/bitcoin/src/script/parsing.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/check.o: deps/bitcoin/src/util/check.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS) -I build

build/randomenv.o: deps/bitcoin/src/randomenv.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS) -I build

build/clientversion.o: deps/bitcoin/src/clientversion.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS) -I build

build/bip32.o: deps/bitcoin/src/util/bip32.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/outputtype.o: deps/bitcoin/src/outputtype.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/logging.o: deps/bitcoin/src/logging.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/time.o: deps/bitcoin/src/util/time.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/miniscript.o: deps/bitcoin/src/script/miniscript.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/threadnames.o: deps/bitcoin/src/util/threadnames.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS) -I build

build/fs.o: deps/bitcoin/src/util/fs.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/syserror.o: deps/bitcoin/src/util/syserror.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS) -I build

build/univalue.o: deps/bitcoin/src/univalue/lib/univalue.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS) -I deps/bitcoin/src/univalue/include

build/univalue_read.o: deps/bitcoin/src/univalue/lib/univalue_read.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS) -I deps/bitcoin/src/univalue/include

build/precomputed_ecmult_gen.o: deps/bitcoin/src/secp256k1/src/precomputed_ecmult_gen.c $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANG) -c $< \
		-o $@ \
		$(CFLAGS) \
		-DENABLE_MODULE_EXTRAKEYS \
		-DENABLE_MODULE_SCHNORRSIG \
		-DECMULT_WINDOW_SIZE=6 \
		-I deps/bitcoin/src/secp256k1/include

build/chainparams.o: deps/bitcoin/src/chainparams.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/kernel_chainparams.o: deps/bitcoin/src/kernel/chainparams.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/args.o: deps/bitcoin/src/common/args.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS) -I deps/bitcoin/src/univalue/include

build/chaintype.o: deps/bitcoin/src/util/chaintype.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/univalue_get.o: deps/bitcoin/src/univalue/lib/univalue_get.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS) -I deps/bitcoin/src/univalue/include

build/fs_helpers.o: deps/bitcoin/src/util/fs_helpers.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS) -I build

build/merkle.o: deps/bitcoin/src/consensus/merkle.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/univalue_write.o: deps/bitcoin/src/univalue/lib/univalue_write.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS) -I deps/bitcoin/src/univalue/include

build/settings.o: deps/bitcoin/src/common/settings.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS) -I build -I deps/bitcoin/src/univalue/include

build/deploymentinfo.o: deps/bitcoin/src/deploymentinfo.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/block.o: deps/bitcoin/src/primitives/block.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/chainparamsbase.o: deps/bitcoin/src/chainparamsbase.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/script_error.o: deps/bitcoin/src/script/script_error.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
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
LLVM_CMAKE_OPTIONS += -DLIBCXX_ENABLE_THREADS=ON -DLIBCXX_HAS_PTHREAD_API=ON

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

$(ATOMICS_TARGET):
	cd $(ATOMICS) && \
		make CC=$(CLANG) \
			AR=$(subst clang,llvm-ar,$(CLANG)) \
			CFLAGS="$(BASE_CFLAGS)"

clean:
	rm -rf build/bitcoin_vm build/bitcoin_vm_stripped build/*.o build/*.txt
	cd $(MUSL) && make clean && rm -rf release
	cd $(BUILTINS) && make clean
	cd $(LIBCXX) && rm -rf release
	cd $(ATOMICS) && make clean

.PHONY: clean all
