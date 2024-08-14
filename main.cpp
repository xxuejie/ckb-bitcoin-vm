#include <jsonlite.h>
#include <policy/policy.h>
#include <primitives/transaction.h>
#include <script/interpreter.h>
#include <script/script.h>
#include <script/script_error.h>
#include <streams.h>

#include <cassert>
#include <cstdio>
#include <cstring>

#include "ckb.h"

typedef enum {
  s_not_interested = 0,
  s_version,
  s_locktime,
  s_vin,
  s_vin_sequence,
  s_vin_txid,
  s_vin_vout,
  s_vin_scriptsig,
  s_vin_prevout,
  s_vin_prevout_scriptpubkey,
  s_vin_prevout_value,
  s_vin_witness,
  s_vout,
  s_vout_scriptpubkey,
  s_vout_value,
} JsonState;

typedef struct {
  JsonState state;
  std::vector<CTxOut> spent_outputs;
  CMutableTransaction mtx;
} Context;

static const size_t DEPTH = 32;

static void key_found(jsonlite_callback_context *c, jsonlite_token *t) {
  size_t len = t->end - t->start;
  Context *context = (Context *)c->client_state;

  if ((context->state == s_not_interested) && (len == 3) &&
      (memcmp(t->start, "vin", 3) == 0)) {
    context->state = s_vin;
  } else if ((context->state == s_not_interested) && (len == 4) &&
             (memcmp(t->start, "vout", 4) == 0)) {
    context->state = s_vout;
  } else if ((context->state == s_not_interested) && (len == 7) &&
             (memcmp(t->start, "version", 7) == 0)) {
    context->state = s_version;
  } else if ((context->state == s_not_interested) && (len == 8) &&
             (memcmp(t->start, "locktime", 8) == 0)) {
    context->state = s_locktime;
  } else if ((context->state == s_vin) && (len == 7) &&
             (memcmp(t->start, "prevout", 7) == 0)) {
    context->state = s_vin_prevout;
  } else if ((context->state == s_vin) && (len == 7) &&
             (memcmp(t->start, "witness", 7) == 0)) {
    context->state = s_vin_witness;
  } else if ((context->state == s_vin) && (len == 8) &&
             (memcmp(t->start, "sequence", 8) == 0)) {
    context->state = s_vin_sequence;
  } else if ((context->state == s_vin) && (len == 4) &&
             (memcmp(t->start, "txid", 4) == 0)) {
    context->state = s_vin_txid;
  } else if ((context->state == s_vin) && (len == 4) &&
             (memcmp(t->start, "vout", 4) == 0)) {
    context->state = s_vin_vout;
  } else if ((context->state == s_vin) && (len == 9) &&
             (memcmp(t->start, "scriptsig", 9) == 0)) {
    context->state = s_vin_scriptsig;
  } else if ((context->state == s_vin_prevout) && (len == 12) &&
             (memcmp(t->start, "scriptpubkey", 12) == 0)) {
    context->state = s_vin_prevout_scriptpubkey;
  } else if ((context->state == s_vin_prevout) && (len == 5) &&
             (memcmp(t->start, "value", 5) == 0)) {
    context->state = s_vin_prevout_value;
  } else if ((context->state == s_vout) && (len == 12) &&
             (memcmp(t->start, "scriptpubkey", 12) == 0)) {
    context->state = s_vout_scriptpubkey;
  } else if ((context->state == s_vout) && (len == 5) &&
             (memcmp(t->start, "value", 5) == 0)) {
    context->state = s_vout_value;
  }
}

static void number_found(jsonlite_callback_context *c, jsonlite_token *t) {
  Context *context = (Context *)c->client_state;

  if (context->state == s_vin_sequence) {
    char *end = (char *)t->end;
    uint64_t value = strtoll((const char *)t->start, &end, 10);
    context->mtx.vin.back().nSequence = (uint32_t)value;
    context->state = s_vin;
  } else if (context->state == s_vin_vout) {
    char *end = (char *)t->end;
    uint64_t value = strtoll((const char *)t->start, &end, 10);
    context->mtx.vin.back().prevout.n = (uint32_t)value;
    context->state = s_vin;
  } else if (context->state == s_vin_prevout_value) {
    char *end = (char *)t->end;
    uint64_t value = strtoll((const char *)t->start, &end, 10);
    context->spent_outputs.back().nValue = value;
    context->state = s_vin_prevout;
  } else if (context->state == s_vout_value) {
    char *end = (char *)t->end;
    uint64_t value = strtoll((const char *)t->start, &end, 10);
    context->mtx.vout.back().nValue = value;
    context->state = s_vout;
  } else if (context->state == s_version) {
    char *end = (char *)t->end;
    uint64_t value = strtoll((const char *)t->start, &end, 10);
    context->mtx.version = value;
    context->state = s_not_interested;
  } else if (context->state == s_locktime) {
    char *end = (char *)t->end;
    uint64_t value = strtoll((const char *)t->start, &end, 10);
    context->mtx.nLockTime = value;
    context->state = s_not_interested;
  }
}

static void string_found(jsonlite_callback_context *c, jsonlite_token *t) {
  Context *context = (Context *)c->client_state;

  if (context->state == s_vin_txid) {
    std::string s((const char *)t->start, t->end - t->start);
    Txid hash = Txid::FromUint256(uint256::FromHex(s).value());
    context->mtx.vin.back().prevout.hash = hash;
    context->state = s_vin;
  } else if (context->state == s_vin_scriptsig) {
    std::string s((const char *)t->start, t->end - t->start);
    if (IsHex(s)) {
      std::vector<uint8_t> sig = ParseHex(s);
      context->mtx.vin.back().scriptSig = CScript(sig.begin(), sig.end());
    }
    context->state = s_vin;
  } else if (context->state == s_vin_prevout_scriptpubkey) {
    std::string s((const char *)t->start, t->end - t->start);
    assert(IsHex(s));
    std::vector<uint8_t> sig = ParseHex(s);
    context->spent_outputs.back().scriptPubKey =
        CScript(sig.begin(), sig.end());
    context->state = s_vin_prevout;
  } else if (context->state == s_vin_witness) {
    std::string s((const char *)t->start, t->end - t->start);
    assert(IsHex(s));
    std::vector<uint8_t> sig = ParseHex(s);
    context->mtx.vin.back().scriptWitness.stack.push_back(sig);
  } else if (context->state == s_vout_scriptpubkey) {
    std::string s((const char *)t->start, t->end - t->start);
    assert(IsHex(s));
    std::vector<uint8_t> sig = ParseHex(s);
    context->mtx.vout.back().scriptPubKey = CScript(sig.begin(), sig.end());
    context->state = s_vout;
  }
}

static void object_start(jsonlite_callback_context *c) {
  Context *context = (Context *)c->client_state;

  if (context->state == s_vin) {
    context->spent_outputs.push_back(CTxOut());
    context->mtx.vin.push_back(CTxIn());
  } else if (context->state == s_vout) {
    context->mtx.vout.push_back(CTxOut());
  }
}

static void object_end(jsonlite_callback_context *c) {
  Context *context = (Context *)c->client_state;

  if (context->state == s_vin_prevout) {
    context->state = s_vin;
  }
}

static void array_end(jsonlite_callback_context *c) {
  Context *context = (Context *)c->client_state;

  if (context->state == s_vin) {
    context->state = s_not_interested;
  } else if (context->state == s_vout) {
    context->state = s_not_interested;
  } else if (context->state == s_vin_witness) {
    context->state = s_vin;
  }
}

int main(int argc, char *argv[]) {
  if (argc != 2) {
    printf("Usage: %s <Bitcoin TX in mempool API JSON response format>\n",
           argv[0]);
    return 1;
  }

  Context context;
  uint8_t parser_memory[jsonlite_parser_estimate_size(DEPTH)];
  uint8_t buffer_memory[jsonlite_static_buffer_size() + 64];
  jsonlite_buffer buffer =
      jsonlite_static_buffer_init(buffer_memory, sizeof(buffer_memory));
  jsonlite_parser parser =
      jsonlite_parser_init(parser_memory, sizeof(parser_memory), buffer);
  jsonlite_parser_callbacks cbs = {
      .parse_finished = jsonlite_default_callbacks.parse_finished,
      .object_start = object_start,
      .object_end = object_end,
      .array_start = jsonlite_default_callbacks.array_start,
      .array_end = array_end,
      .true_found = jsonlite_default_callbacks.true_found,
      .false_found = jsonlite_default_callbacks.false_found,
      .null_found = jsonlite_default_callbacks.null_found,
      .key_found = key_found,
      .string_found = string_found,
      .number_found = number_found,
      .context = {.client_state = &context}};
  jsonlite_parser_set_callback(parser, &cbs);
  jsonlite_result result =
      jsonlite_parser_tokenize(parser, argv[1], strlen(argv[1]));
  assert(result == jsonlite_result_ok);

  CTransaction tx(context.mtx);

  // This is in fact EncodeHexTx but core_write.cpp has blockers
  // DataStream ssTx;
  // ssTx << TX_WITH_WITNESS(tx);
  // std::string hex_tx = HexStr(ssTx);
  // printf("TX: %s\n", hex_tx.c_str());

  PrecomputedTransactionData txdata;
  txdata.Init(tx, std::move(context.spent_outputs));
  for (size_t i = 0; i < tx.vin.size(); i++) {
    ScriptError error = SCRIPT_ERR_OK;
    TransactionSignatureChecker checker(
        &tx, i, txdata.m_spent_outputs[i].nValue, txdata,
        MissingDataBehavior::ASSERT_FAIL);

    uint64_t before = ckb_current_cycles();
    bool result = VerifyScript(tx.vin[i].scriptSig,
                               txdata.m_spent_outputs[i].scriptPubKey,
                               &tx.vin[i].scriptWitness,
                               STANDARD_SCRIPT_VERIFY_FLAGS, checker, &error);
    uint64_t after = ckb_current_cycles();

    if (!result) {
      printf("Error verifying vin %ld: %s\n", i,
             ScriptErrorString(error).c_str());
      return -2;
    }

    printf("Vin %ld takes %lu cycles to validate\n", i, (after - before));
  }

  return 0;
}
