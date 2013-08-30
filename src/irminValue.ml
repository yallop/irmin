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

open IrminTypes
open IrminMisc

module Make (K: KEY)  (B: VALUE with module Key = K) = struct

  let debug fmt = IrminMisc.debug "VALUE" fmt

  module Blob = B

  module Key = K

  module Keys = IrminIO.List(K)

  type revision = {
    parents : Key.Set.t;
    contents: Key.t;
  }

  type t =
    | Blob of Blob.t
    | Revision of revision

  let of_string str =
    Blob (B.of_string str)

  let to_string = function
    | Blob b     -> B.to_string b
    | Revision _ -> None

  let revision contents parents =
    Revision { contents; parents }

  module Revision = struct

    let debug fmt = IrminMisc.debug "REVISION" fmt

    let pretty r =
      Printf.sprintf "[parents:%s | contents:%s]"
        (K.Set.pretty r.parents) (K.pretty r.contents)

    let of_json (json:IrminJSON.t) = match json with
      | `O [ ("parents", parents); ("contents", contents) ] ->
        let parents = IrminJSON.to_list K.of_json parents in
        let parents = Key.Set.of_list parents in
        let contents = K.of_json contents in
        { parents; contents }
      | _ -> IrminIO.parse_error "Revision.of_json"

    let to_json r =
      let parents = IrminJSON.of_list K.to_json (Key.Set.to_list r.parents) in
      let contents = K.to_json r.contents in
      `O [ ("parents", parents); ("contents", contents) ]

    let sizeof t =
      debug "sizeof";
      Keys.sizeof (t.contents :: Key.Set.to_list t.parents)

    let read buf =
      debug "read";
      let keys = Keys.read buf in
      match keys with
      | []   -> IrminIO.parse_error_buf buf "Revision.read"
      | h::t -> { contents = h; parents = Key.Set.of_list t }

    let write buf t =
      debug "write %s" (pretty t);
      Keys.write buf (t.contents :: Key.Set.to_list t.parents)

    let equal r1 r2 =
      Key.equal r1.contents r2.contents
      && Key.Set.cardinal r1.parents = Key.Set.cardinal r2.parents
      && Key.Set.equal r1.parents r2.parents

    let compare r1 r2 =
      match Key.compare r1.contents r2.contents with
      | 0 -> Key.Set.compare r1.parents r2.parents
      | i -> i

  end

  let pretty = function
    | Blob b     -> "B" ^ Blob.pretty b
    | Revision r -> "R" ^ Revision.pretty r

  let to_json = function
    | Blob b     -> `O [ "blob"    , Blob.to_json b ]
    | Revision r -> `O [ "revision", Revision.to_json r ]

  let of_json = function
    | `O [ "blob"    , json ] -> Blob (Blob.of_json json)
    | `O [ "revision", json ] -> Revision (Revision.of_json json)
    | _ -> IrminIO.parse_error "value_of_json"

  let sizeof t =
    debug "sizeof";
    1
    + match t with
      | Blob b     -> Blob.sizeof b
      | Revision r -> Revision.sizeof r

  let read buf =
    debug "read";
    let kind = IrminIO.get_uint8 buf in
    match kind with
    | 0 -> Blob (Blob.read buf)
    | 1 -> Revision (Revision.read buf)
    | _ -> IrminIO.parse_error_buf buf "Value.of_cstruct"

  let write buf t =
    debug "write %s" (pretty t);
    let kind = match t with
      | Blob _     -> 0
      | Revision _ -> 1 in
    IrminIO.set_uint8 buf kind;
    IrminIO.dump_buffer buf;
    let () = match t with
      | Blob b     -> Blob.write buf b
      | Revision r -> Revision.write buf r in
    IrminIO.dump_buffer buf

  let parents = function
    | Revision { parents } -> parents
    | Blob _               -> Key.Set.empty

  let contents = function
    | Revision { contents } -> Some contents
    | Blob _                -> None

  let key = function
    | Blob b     -> B.key b
    | Revision r -> Key.concat (r.contents :: Key.Set.to_list r.parents)

  let merge merge_keys v1 v2 =
    if v1 = v2 then Some v1
    else match v1, v2 with
      | Blob b1    , Blob b2     ->
        begin match B.merge merge_keys b1 b2 with
          | None   -> None
          | Some b -> Some (Blob b)
        end
      | Revision r1, Revision r2 ->
        let parents = Key.Set.of_list [key v1; key v2] in
        begin match merge_keys r1.contents r2.contents with
          | None          -> None
          | Some contents -> Some (Revision { parents; contents })
        end
      | _ -> None

  let equal v1 v2 =
    match v1, v2 with
    | Blob b1    , Blob b2     -> B.equal b1 b2
    | Revision r1, Revision r2 -> Revision.equal r1 r2
    | _ -> false

  let compare v1 v2 =
    match v1, v2 with
    | Blob _     , Revision _  -> 1
    | Revision _ , Blob _      -> -1
    | Blob b1    , Blob b2     -> B.compare b1 b2
    | Revision r1, Revision r2 -> Revision.compare r1 r2

  module Set = IrminMisc.SetMake(struct
      type tmp = t
      type t = tmp
      let compare = compare
      let pretty = pretty
    end)

end

type blob = B of string

module Blob (K: KEY) = struct

  include IrminIO.String(struct
      type t = blob
      let to_string (B s) = s
      let of_string s = B s
    end)

  let merge _ b1 b2 = None

  let parents _ = K.Set.empty

  let contents _ = None

  let key (B str) =
    K.of_string str

  module Key = K

  let of_string str = B str

  let to_string (B str) = Some str

  let revision _ =
    failwith "Blob.revision"

  let equal (B b1) (B b2) = String.compare b1 b1 = 0
end