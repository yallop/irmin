(*
 * Copyright (c) 2013 Thomas Gazagnaire <thomas@gazagnaire.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

open IrminLwt
open OUnit
open Test_common

let v1 = Value.of_string "foo"
let v2 = Value.of_string ""
let k1 = Value.key v1
let k2 = Value.key v2
let k1s = Key.Set.singleton k1
let k2s = Key.Set.singleton k2
let t1 = Tag.of_string "foo"
let t2 = Tag.of_string "bar"

let test_keys () =
  let module KV = Disk.Key_store in
  let test t =
    lwt () = KV.add t k1 k2s in
    lwt nil' = KV.pred t k2 in
    lwt k2s' = KV.pred t k1 in
    lwt ks = KV.all t in
    assert_keys_equal "nil" Key.Set.empty nil';
    assert_keys_equal "k2" k2s k2s';
    assert_keys_equal "list" (Key.Set.union k1s k2s) ks;
    Lwt.return ()
  in
  Lwt_unix.run (with_db test_db test)

let test_values () =
  let module DV = Disk.Value_store in
  let test t =
    lwt k1 = DV.write t v1 in
    lwt k1' = DV.write t v1 in
    lwt k2 = DV.write t v2 in
    lwt k2' = DV.write t v2 in
    lwt v1' = DV.read t k1 in
    lwt v2' = DV.read t k2 in
    assert_key_equal "k1" k1 k1';
    assert_key_equal "k2" k2 k2';
    assert_value_opt_equal "v1" (Some v1) v1';
    assert_value_opt_equal "v2" (Some v2) v2';
    Lwt.return ()
  in
  Lwt_unix.run (with_db test_db test)

let test_tags () =
  let module KT = Disk.Tag_store in
  let test t =
    lwt () = KT.update t t1 k1s in
    lwt () = KT.update t t2 k2s in
    lwt k1s' = KT.read t t1 in
    lwt k2s' = KT.read t t2 in
    assert_keys_equal "t1" k1s k1s';
    assert_keys_equal "t2" k2s k2s';
    lwt () = KT.update t t1 k2s in
    lwt k2s'' = KT.read t t1 in
    assert_keys_equal "t1-after-update" k2s k2s'';
    lwt set = KT.all t in
    assert_tags_equal "all" (Tag.Set.of_list [t1; t2]) set;
    lwt () = KT.remove t t1 in
    lwt empty = KT.read t t1 in
    assert_keys_equal "empty" Key.Set.empty empty;
    lwt set = KT.all t in
    assert_tags_equal "all-after-remove" (Tag.Set.singleton t2) set;
    Lwt.return ()
  in
  Lwt_unix.run (with_db test_db test)

let suite =
  "DISK",
  [
    "Basic disk operations for values", test_values;
    "Basic disk operations for keys"  , test_keys;
    "Basic disk operations for tags"  , test_tags;
  ]