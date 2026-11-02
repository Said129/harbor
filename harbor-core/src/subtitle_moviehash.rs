//! Original Harbor Desktop 0.9.132 OpenSubtitles hash arithmetic. Native hosts own bounded IO.
#[cfg(test)]
const CHUNK: u64 = 65536;

fn sum_u64_le(buf: &[u8]) -> u64 {
    let mut sum: u64 = 0;
    let mut i = 0;
    while i + 8 <= buf.len() {
        let mut v = [0u8; 8];
        v.copy_from_slice(&buf[i..i + 8]);
        sum = sum.wrapping_add(u64::from_le_bytes(v));
        i += 8;
    }
    sum
}

pub fn hash_from_ends(size: u64, head: &[u8], tail: &[u8]) -> String {
    let h = size
        .wrapping_add(sum_u64_le(head))
        .wrapping_add(sum_u64_le(tail));
    format!("{:016x}", h)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn zero_ends_hash_equals_size() {
        let head = vec![0u8; CHUNK as usize];
        let tail = vec![0u8; CHUNK as usize];
        assert_eq!(hash_from_ends(131072, &head, &tail), "0000000000020000");
    }

    #[test]
    fn wrapping_sum_matches_manual() {
        let buf = vec![1u8; CHUNK as usize];
        let per = 0x0101010101010101u64;
        let n = CHUNK / 8;
        let ones = per.wrapping_mul(n);
        let expect = 200000u64.wrapping_add(ones).wrapping_add(ones);
        assert_eq!(
            hash_from_ends(200000, &buf, &buf),
            format!("{:016x}", expect)
        );
    }
}
