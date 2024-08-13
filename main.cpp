#include <primitives/transaction.h>
#include <script/interpreter.h>
#include <script/script.h>
#include <streams.h>
#include <univalue/include/univalue.h>

#include <cassert>
#include <cstdio>
#include <cstring>

int main(int argc, char* argv[]) {
  if (argc != 2) {
    printf("Usage: %s <Bitcoin TX in mempool API JSON response format>\n",
           argv[0]);
    return 1;
  }

  UniValue root_value;
  assert(root_value.read(argv[1]));
  const UniValue& root_obj = root_value.get_obj();

  CMutableTransaction mtx;
  mtx.version = root_obj.find_value("version").getInt<uint32_t>();
  mtx.nLockTime = root_obj.find_value("locktime").getInt<uint32_t>();

  const UniValue& vins = root_obj.find_value("vin").get_array();
  for (size_t i = 0; i < vins.size(); i++) {
    const UniValue& vin = vins[i].get_obj();

    CTxIn cin;
    cin.nSequence = vin.find_value("sequence").getInt<uint32_t>();

    Txid hash = Txid::FromUint256(
        uint256::FromHex(vin.find_value("txid").get_str()).value());
    uint32_t n = vin.find_value("vout").getInt<uint32_t>();
    cin.prevout = COutPoint(hash, n);

    std::string sig_str = vin.find_value("scriptsig").get_str();
    if (IsHex(sig_str)) {
      std::vector<uint8_t> sig = ParseHex(sig_str);
      cin.scriptSig = CScript(sig.begin(), sig.end());
    }

    if (vin.exists("witness")) {
      const UniValue& witnesses = vin.find_value("witness").get_array();
      for (size_t j = 0; j < witnesses.size(); j++) {
        const std::string& witness = witnesses[j].get_str();
        assert(IsHex(witness));

        cin.scriptWitness.stack.push_back(ParseHex(witness));
      }
    }

    mtx.vin.push_back(cin);
  }

  const UniValue& vouts = root_obj.find_value("vout").get_array();
  for (size_t i = 0; i < vouts.size(); i++) {
    const UniValue& vout = vouts[i].get_obj();

    CTxOut cout;
    cout.nValue = vout.find_value("value").getInt<int64_t>();

    const std::string& pubkey_str = vout.find_value("scriptpubkey").get_str();
    if (IsHex(pubkey_str)) {
      std::vector<uint8_t> pubkey = ParseHex(pubkey_str);
      cout.scriptPubKey = CScript(pubkey.begin(), pubkey.end());
    }

    mtx.vout.push_back(cout);
  }

  CTransaction tx(mtx);

  // This is in fact EncodeHexTx but core_write.cpp has blockers
  DataStream ssTx;
  ssTx << TX_WITH_WITNESS(tx);
  std::string hex_tx = HexStr(ssTx);

  printf("TX: %s\n", hex_tx.c_str());

  return 0;
}
