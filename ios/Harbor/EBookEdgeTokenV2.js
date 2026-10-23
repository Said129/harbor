// SPDX-License-Identifier: LGPL-3.0-only
// Edge v2 protocol arithmetic adapted from rany2/edge-tts drm.py.
// The complete license and rebuild source location are in EBookNarrationNotices.txt.

globalThis.harborEdgeTokenV2 = (() => {
  const sha256_initial = [
    1779033703, 3144134277, 1013904242, 2773480762, 1359893119, 2600822924, 528734635, 1541459225,
  ];
  const sha256_state = [
    4255104674, 2435071207, 3192492180, 3442351626, 1811967817, 79508907, 4272990180, 66059218,
  ];
  const sha256_schedule = [
    3945054110, 358115615, 2696978146, 217723578, 2787307148, 3520959633, 3235718560, 4192668342,
    4039316851, 1884868174, 1904797190, 15051571, 3529027680, 1920361828,
  ];
  const sha256_round_constants = [
    1116352408, 1899447441, 3049323471, 3921009573, 961987163, 1508970993, 2453635748, 2870763221,
    3624381080, 310598401, 607225278, 1426881987, 1925078388, 2162078206, 2614888103, 3248222580,
    3835390401, 4022224774, 264347078, 604807628, 770255983, 1249150122, 1555081692, 1996064986,
    2554220882, 2821834349, 2952996808, 3210313671, 3336571891, 3584528711, 113926993, 338241895,
    666307205, 773529912, 1294757372, 1396182291, 1695183700, 1986661051, 2177026350, 2456956037,
    2730485921, 2820302411, 3259730800, 3345764771, 3516065817, 3600352804, 4094571909, 275423344,
    430227734, 506948616, 659060556, 883997877, 958139571, 1322822218, 1537002063, 1747873779,
    1955562222, 2024104815, 2227730452, 2361852424, 2428436474, 2756734187, 3204031479, 3329325298,
  ];
  const cs64_coefficients = [
    [3895366065, 3005677776],
    [1155409094, 2296378653],
    [1005282748, 693190712],
    [3365689651, 3005795295],
    [2367603217, 3557143765],
    [827258325, 652566332],
    [3911487921, 1618477510],
    [4037392853, 2192753147],
    [101076211, 4199654362],
    [3665427040, 545047652],
    [3201434976, 1010595059],
    [2314848760, 3536931681],
    [905590982, 3137643201],
    [3410617286, 3311559015],
  ];

  const add = (...values) => values.reduce((sum, value) => sum + value, 0) >>> 0;
  const mul = (a, b) => Math.imul(a, b) >>> 0;
  const rotate = (value, count) => (value >>> count) | (value << (32 - count));
  const swap = (value) => ((value << 16) | (value >>> 16)) >>> 0;
  const sigma0 = (value) => (rotate(value, 7) ^ rotate(value, 18) ^ (value >>> 3)) >>> 0;
  const sigma1 = (value) => (rotate(value, 17) ^ rotate(value, 19) ^ (value >>> 10)) >>> 0;
  const be = (values) => values.reduce((sum, value) => sum * 256 + value, 0) >>> 0;
  const le = (values) => be([...values].reverse());
  const bytes = (value) => [value >>> 24, (value >>> 16) & 255, (value >>> 8) & 255, value & 255];
  const hex = (values) =>
    values
      .map((value) => value.toString(16).padStart(2, "0"))
      .join("")
      .toUpperCase();
  function expand(words, start = 16) {
    for (let index = start; index < 64; index += 1)
      words.push(
        add(
          sigma1(words[index - 2]),
          words[index - 7],
          sigma0(words[index - 15]),
          words[index - 16],
        ),
      );
  }
  function rounds(state, words, first = 0) {
    let [a, b, c, d, e, f, g, h] = state;
    for (let index = first; index < 64; index += 1) {
      const constant = first === 14 && index === 14 ? 0xc9dc06a7 : sha256_round_constants[index];
      const t1 = add(
        h,
        rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25),
        g ^ (e & (f ^ g)),
        constant,
        words[index],
      );
      const t2 = add(rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22), (a & b) | (c & (a | b)));
      [a, b, c, d, e, f, g, h] = [add(t1, t2), a, b, c, add(d, t1), e, f, g];
    }
    return [a, b, c, d, e, f, g, h];
  }
  function digest(data) {
    const words = Array(14)
      .fill(0)
      .concat([be(data.slice(0, 3)), be(data.slice(3, 7))]);
    for (let index = 16; index < 30; index += 1) {
      let value = sha256_schedule[index - 16];
      if (index - 2 >= 14)
        value = add(value, sigma1(words[index - 2]) ^ (index === 16 ? 0x000b92c0 : 0));
      if (index - 7 >= 14) value = add(value, words[index - 7]);
      if (index - 15 >= 14)
        value = add(value, sigma0(words[index - 15]) ^ (index === 29 ? 0x059c0b80 : 0));
      words.push(value >>> 0);
    }
    words.push(
      add(
        sigma1(words[28]),
        words[23],
        sigma0(words[15]),
        words[14],
        0xc9dc06a7,
        -sha256_round_constants[14],
      ),
    );
    expand(words, 31);
    let state = rounds(sha256_state, words, 14).map((value, index) =>
      add(value, sha256_initial[index]),
    );
    const length = 57 + data.length;
    const padded = data
      .slice(7)
      .concat(
        [128],
        Array((((55 - length) % 64) + 64) % 64).fill(0),
        [0, 0, 0, 0],
        bytes(length * 8),
      );
    for (let offset = 0; offset < padded.length; offset += 64) {
      const block = [];
      for (let index = 0; index < 16; index += 1)
        block.push(be(padded.slice(offset + index * 4, offset + index * 4 + 4)));
      expand(block);
      state = rounds(state, block).map((value, index) => add(value, state[index]));
    }
    return state.flatMap(bytes);
  }
  function cs64(data, hash) {
    const keyA = (le(hash.slice(0, 4)) | 1) >>> 0,
      keyB = (le(hash.slice(4, 8)) | 1) >>> 0;
    const factors = [mul(keyA, 0x82893933), mul(keyB, 0x82893933)];
    const terms = cs64_coefficients.map(([coefficient], index) =>
      mul(coefficient, factors[index % 2]),
    );
    const offsets = cs64_coefficients.map(([, offset]) => offset);
    const padded = [0].concat(data);
    while (padded.length % 8) padded.push(0);
    for (let index = 0; index < padded.length / 4; index += 1) {
      const word = le(padded.slice(index * 4, index * 4 + 4));
      terms.push(
        add(mul(word, index % 2 ? keyB : keyA), index === 0 ? mul(0xf2f90b1a, factors[0]) : 0),
      );
      offsets.push(
        add(mul(swap(word), index % 2 ? 0xc31713db : 0xef0569fb), index === 0 ? 0x0b1a0000 : 0),
      );
    }
    let swapAcc = 0,
      swapLast = 0,
      state = 0,
      acc = 0;
    for (let index = 0; index < terms.length; index += 2) {
      const x = terms[index],
        y = terms[index + 1];
      let q = mul(swap(add(offsets[index], x)), 0x76f50f34);
      swapAcc = add(swapAcc, mul(swap(q), 0xc3efea97), q);
      q = mul(swap(add(offsets[index + 1], y)), 0x1881ce3c);
      swapLast = add(mul(swap(q), 0x35bd1ec9), q);
      swapAcc = add(swapAcc, swapLast);
      state = add(mul(state, keyA), x);
      for (const coefficient of [0xcf98b111, 0x87085b9f, 0x12ceb96d, 0x257e1d83])
        state = mul(swap(state), coefficient);
      acc = add(acc, state);
      let value = add(mul(state, keyB), y);
      for (const coefficient of [0xa27416f5, 0xd38396ff, 0x7c932b89, 0xbfa49f69])
        value = mul(swap(value), coefficient);
      state = value;
      acc = add(acc, state);
    }
    return [(swapLast ^ state) >>> 0, (swapAcc ^ acc) >>> 0].flatMap((value) =>
      bytes(value).reverse(),
    );
  }
  return (salt) => {
    if (typeof salt !== "string" || !/^[0-9]{17,19}6A5AA1D4EAFF4E9FB37E23D68491D6F4$/.test(salt))
      throw new Error("Invalid Edge token input");
    const data = [...salt].map((value) => value.charCodeAt(0)),
      hash = digest(data);
    return hex(cs64(data, hash)) + "-" + hex(hash);
  };
})();
