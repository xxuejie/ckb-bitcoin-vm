CLANG := clang-18
CLANGXX := $(subst clang,clang++,$(CLANG))
LD := $(subst clang,ld.lld,$(CLANG))

MUSL := $(realpath deps/musl)
BUILTINS := $(realpath deps/builtins)
LIBCXX := $(realpath deps/libcxx)

MUSL_TARGET := $(MUSL)/release/include/stddef.h
BUILTINS_TARGET := $(BUILTINS)/build/libcompiler-rt.a
LIBCXX_TARGET := $(LIBCXX)/release/include/c++/v1/vector

CXXFLAGS := --target=riscv64 -march=rv64imc_zba_zbb_zbc_zbs \
  -g -O3 \
  -std=c++20 \
  -D_GNU_SOURCE \
  -nostdinc -nostdinc++ \
  -isystem $(LIBCXX)/release/include/c++/v1 \
  -isystem $(MUSL)/release/include \
  -I deps/bitcoin/src \
  -fvisibility=hidden \
  -fdata-sections -ffunction-sections
LDFLAGS := --gc-sections --static \
  --nostdlib --sysroot $(MUSL)/release \
  -L$(MUSL)/release/lib -L$(BUILTINS)/build \
  -lc -lgcc -lcompiler-rt \
  -L$(LIBCXX)/release/lib \
  -lc++ -lc++abi -lunwind

all: build/bitcoin_vm

BITCOIN_LIBS := univalue_get.o univalue_read.o univalue.o \
	transaction.o \
	script.o \
	hex_base.o sha256.o \
	strencodings.o \
	cleanse.o \
	streams.o uint256.o

build/bitcoin_vm: build/main.o $(foreach o,$(BITCOIN_LIBS),build/$(o)) $(BUILTINS_TARGET)
	$(LD) $< $(foreach o,$(BITCOIN_LIBS),build/$(o)) -o $@ $(LDFLAGS)

build/%.o: %.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

build/%.o: deps/bitcoin/src/univalue/lib/%.cpp $(MUSL_TARGET) $(LIBCXX_TARGET)
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS) -I deps/bitcoin/src/univalue/include

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
	$(CLANGXX) -c $< -o $@ $(CXXFLAGS)

$(MUSL_TARGET):
	cd $(MUSL) && \
		CLANG=$(CLANG) ./ckb/build.sh

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

$(LIBCXX_TARGET): $(MUSL_TARGET)
	cd $(LIBCXX) && \
		CLANG=$(CLANG) \
			MUSL=$(MUSL)/release \
			LIBCXXABI_CMAKE_OPTIONS="-DLIBCXXABI_NON_DEMANGLING_TERMINATE=ON" \
		  ./build.sh
	touch $@

clean:
	rm -rf build/bitcoin_vm build/*.o
	cd $(MUSL) && make clean && rm -rf release
	cd $(BUILTINS) && make clean
	cd $(LIBCXX) && rm -rf release

.PHONY: clean all
