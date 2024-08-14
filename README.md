# ckb-bitcoin-vm

This project serves as a demonstration on validating Bitcoin Scripts on CKB-VM. Specifically, it accepts full Bitcoin transaction in [mempool's API response format](https://mempool.space/docs/api/rest#get-transaction) as a CLI argument, parses the Bitcoin transaction, and run all Bitcoin script validations.

## Usage:

```bash
$ git clone --recursive https://github.com/xxuejie/ckb-bitcoin-vm
$ make
# If you are using mac OS, do:
$ make CLANG=clang
$ ckb-debugger --bin build/bitcoin_vm bitcoin_vm "$(curl -s https://mempool.space/api/tx/382b61d20ad4fce5764aae6f4d4e7fa10abbb3f9ed8692fb262b70a3ed494d5c)"
Vin 0 takes 867821
 cycles to validate
Run result: 0
Total cycles consumed: 1749091(1.7M)
Transfer cycles: 408569(399.0K), running cycles: 1340522(1.3M)
# Or you can also save the transaction in a local file, and run it repeatedly:
$ curl https://mempool.space/api/tx/15e10745f15593a899cef391191bdd3d7c12412cc4696b7bcb669d0feadc8521 > nowitness1.json
$ ckb-debugger --bin build/bitcoin_vm bitcoin_vm "$(<nowitness1.json)"
Vin 0 takes 879334
 cycles to validate
Vin 1 takes 873915
 cycles to validate
Vin 2 takes 890224
 cycles to validate
Vin 3 takes 888659
 cycles to validate
Vin 4 takes 888927
 cycles to validate
Run result: 0
Total cycles consumed: 6234489(5.9M)
Transfer cycles: 409733(400.1K), running cycles: 5824756(5.6M)
```
