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

BASE_CFLAGS := --target=riscv64 -march=rv64imc_zba_zbb_zbc_zbs \
	-Os \
	-fdata-sections -ffunction-sections -fvisibility=hidden
CFLAGS := $(BASE_CFLAGS) \
  -g \
  -Wall -Werror \
  -Wno-unused-function \
  -nostdinc \
  -isystem $(MUSL)/release/include
CXXFLAGS := $(BASE_CFLAGS) \
  -g \
  -Wall -Werror \
  -std=c++20 \
  -D_GNU_SOURCE \
  -nostdinc -nostdinc++ \
  -isystem $(LIBCXX)/release/include/c++/v1 \
  -isystem $(MUSL)/release/include \
  -I deps/bitcoin/src
LDFLAGS := --gc-sections --static \
  --nostdlib --sysroot $(MUSL)/release \
  -L$(MUSL)/release/lib -L$(BUILTINS)/build \
  -lc -lgcc -lcompiler-rt \
  -L$(LIBCXX)/release/lib \
  -lc++ -lc++abi -lunwind

all: build/bitcoin_vm build/bitcoin_vm_stripped

BITCOIN_LIBS := \
	transaction.o \
	script.o script_error.o interpreter.o \
	hex_base.o sha256.o sha1.o ripemd160.o \
	strencodings.o \
	cleanse.o \
	streams.o uint256.o hash.o pubkey.o \
	secp256k1.o precomputed_ecmult.o \
	jsonlite.o

build/bitcoin_vm_stripped: build/bitcoin_vm
	$(OBJCOPY) --strip-all $< $@

build/bitcoin_vm: build/main.o $(foreach o,$(BITCOIN_LIBS),build/$(o)) $(BUILTINS_TARGET)
	$(LD) $< $(foreach o,$(BITCOIN_LIBS),build/$(o)) -o $@ $(LDFLAGS)

build/%.o: %.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS) -I deps/jsonlite/amalgamated/jsonlite

build/%.o: deps/jsonlite/amalgamated/jsonlite/%.c $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANG) -c $< -o $@ $(CFLAGS) -I deps/jsonlite/amalgamated/jsonlite

build/%.o: deps/bitcoin/src/primitives/%.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/%.o: deps/bitcoin/src/script/%.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/%.o: deps/bitcoin/src/crypto/%.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS) -I build

build/%.o: deps/bitcoin/src/util/%.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/%.o: deps/bitcoin/src/support/%.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/%.o: deps/bitcoin/src/%.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS) -I deps/bitcoin/src/secp256k1/include

build/%.o: deps/bitcoin/src/secp256k1/src/%.c $(MUSL_TARGET)
	$(CLANG) -c $< \
		-o $@ \
		$(CFLAGS) \
		-DENABLE_MODULE_EXTRAKEYS \
		-DENABLE_MODULE_SCHNORRSIG \
		-DECMULT_WINDOW_SIZE=6 \
		-I deps/bitcoin/src/secp256k1/include

$(MUSL_TARGET):
	cd $(MUSL) && \
		CLANG=$(CLANG) \
			BASE_CFLAGS="$(BASE_CFLAGS) -DPAGE_SIZE=4096 -Os" \
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
LLVM_CMAKE_OPTIONS += -DLIBCXXABI_NON_DEMANGLING_TERMINATE=ON

$(LIBCXX_TARGET): $(MUSL_TARGET)
	cd $(LIBCXX) && \
		CLANG=$(CLANG) \
			DEBUG=1 \
			BASE_CFLAGS="$(BASE_CFLAGS)" \
			MUSL=$(MUSL)/release \
			LLVM_VERSION="18.1.8" \
			LLVM_PATCH="$(realpath llvm_patch)" \
			LLVM_CMAKE_OPTIONS="$(LLVM_CMAKE_OPTIONS)" \
		  ./build.sh
	touch $@

clean:
	rm -rf build/bitcoin_vm build/bitcoin_vm_stripped build/*.o
	cd $(MUSL) && make clean && rm -rf release
	cd $(BUILTINS) && make clean
	cd $(LIBCXX) && rm -rf release

.PHONY: clean all
