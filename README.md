# ckb-bitcoin-vm

This project serves as a demonstration on validating Bitcoin Scripts on CKB-VM. Specifically, it accepts full Bitcoin transaction in [mempool's API response format](https://mempool.space/docs/api/rest#get-transaction) as a CLI argument, parses the Bitcoin transaction, and run all Bitcoin script validations.

## Usage:

```bash
$ git clone --recursive https://github.com/xxuejie/ckb-bitcoin-vm
$ make
# If you are using mac OS, do:
$ make CLANG=clang
$ ckb-debugger --bin build/bitcoin_vm bitcoin_vm "$(curl -s https://mempool.space/api/tx/382b61d20ad4fce5764aae6f4d4e7fa10abbb3f9ed8692fb262b70a3ed494d5c)"
Vin 0 takes 986664
 cycles to validate
Run result: 0
Total cycles consumed: 1605056(1.5M)
Transfer cycles: 128990(126.0K), running cycles: 1476066(1.4M)
# Or you can also save the transaction in a local file, and run it repeatedly:
$ curl https://mempool.space/api/tx/15e10745f15593a899cef391191bdd3d7c12412cc4696b7bcb669d0feadc8521 > nowitness1.json
$ ckb-debugger --bin build/bitcoin_vm bitcoin_vm "$(<nowitness1.json)"
Vin 0 takes 1008698
 cycles to validate
Vin 1 takes 989294
 cycles to validate
Vin 2 takes 1020211
 cycles to validate
Vin 3 takes 1023986
 cycles to validate
Vin 4 takes 1024188
 cycles to validate
Run result: 0
Total cycles consumed: 6612526(6.3M)
Transfer cycles: 130154(127.1K), running cycles: 6482372(6.2M)
```
