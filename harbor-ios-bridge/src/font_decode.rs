//! Bounded local web-font decoding, independent of JSON and network APIs.
use std::{panic::catch_unwind, ptr};

const MAX_INPUT: usize = 32 * 1024 * 1024;
const MAX_OUTPUT: usize = 128 * 1024 * 1024;

fn u16_at(data: &[u8], offset: usize) -> Option<usize> {
    Some(u16::from_be_bytes(data.get(offset..offset + 2)?.try_into().ok()?) as usize)
}
fn u32_at(data: &[u8], offset: usize) -> Option<usize> {
    Some(u32::from_be_bytes(data.get(offset..offset + 4)?.try_into().ok()?) as usize)
}

fn validate_woff1(data: &[u8], tables: usize, expected: usize) -> Option<()> {
    let directory_end = 44 + tables * 20;
    if directory_end > data.len() {
        return None;
    }
    let mut total = 12 + tables * 16;
    for index in 0..tables {
        let row = 44 + index * 20;
        let offset = u32_at(data, row + 4)?;
        let compressed = u32_at(data, row + 8)?;
        let original = u32_at(data, row + 12)?;
        if compressed > original
            || offset < directory_end
            || offset.checked_add(compressed)? > data.len()
        {
            return None;
        }
        total = total.checked_add(original.checked_add(3)? & !3)?;
        if total > MAX_OUTPUT {
            return None;
        }
    }
    (total == expected).then_some(())
}

fn repair_checksum(font: &mut [u8]) -> Option<()> {
    if font.starts_with(b"ttcf") {
        return Some(());
    }
    let tables = u16_at(font, 4)?;
    for index in 0..tables {
        let row = 12 + index * 16;
        if font.get(row..row + 4)? != b"head" {
            continue;
        }
        let offset = u32_at(font, row + 8)?;
        if u32_at(font, row + 12)? < 12 || offset.checked_add(12)? > font.len() {
            return None;
        }
        font[offset + 8..offset + 12].fill(0);
        let sum = font.chunks(4).fold(0_u32, |sum, chunk| {
            let mut word = [0; 4];
            word[..chunk.len()].copy_from_slice(chunk);
            sum.wrapping_add(u32::from_be_bytes(word))
        });
        font[offset + 8..offset + 12]
            .copy_from_slice(&0xb1b0_afba_u32.wrapping_sub(sum).to_be_bytes());
        return Some(());
    }
    Some(())
}

fn decode(data: &[u8]) -> Option<Vec<u8>> {
    if !(44..=MAX_INPUT).contains(&data.len()) || u32_at(data, 8)? != data.len() {
        return None;
    }
    let tables = u16_at(data, 12)?;
    let expected = u32_at(data, 16)?;
    if !(1..=4095).contains(&tables) || !(12..=MAX_OUTPUT).contains(&expected) {
        return None;
    }
    let mut output = match data.get(..4)? {
        b"wOFF" => {
            validate_woff1(data, tables, expected)?;
            wuff::decompress_woff1(data).ok()?
        }
        b"wOF2" => wuff::decompress_woff2(data).ok()?,
        _ => return None,
    };
    if !(12..=MAX_OUTPUT).contains(&output.len()) {
        return None;
    }
    repair_checksum(&mut output)?;
    Some(output)
}

/// Decode WOFF/WOFF2 without uploading data or copying it into a JSON request.
/// Returns a Rust-owned byte slice, or null with output_length=0 on failure.
///
/// # Safety
/// Input must reference `length` readable bytes for this synchronous call.
/// `output_length` must reference writable, non-aliasing usize storage.
/// Free a successful result exactly once with its returned length.
#[no_mangle]
pub unsafe extern "C" fn harbor_ios_font_decode(
    input: *const u8,
    length: usize,
    output_length: *mut usize,
) -> *mut u8 {
    if output_length.is_null() {
        return ptr::null_mut();
    }
    unsafe {
        *output_length = 0;
    }
    if input.is_null() || !(44..=MAX_INPUT).contains(&length) {
        return ptr::null_mut();
    }
    let input = unsafe { std::slice::from_raw_parts(input, length) };
    let Some(output) = catch_unwind(|| decode(input)).ok().flatten() else {
        return ptr::null_mut();
    };
    unsafe {
        *output_length = output.len();
    }
    Box::into_raw(output.into_boxed_slice()) as *mut u8
}

/// # Safety
/// Pass only a live result of harbor_ios_font_decode with its exact original
/// length, once. Null is allowed. No other allocation may be passed here.
#[no_mangle]
pub unsafe extern "C" fn harbor_ios_font_free(data: *mut u8, length: usize) {
    if !data.is_null() && length != 0 {
        drop(unsafe { Box::from_raw(ptr::slice_from_raw_parts_mut(data, length)) });
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn minimal() -> Vec<u8> {
        let mut data = vec![0; 76];
        data[..4].copy_from_slice(b"wOFF");
        data[4..8].copy_from_slice(&0x0001_0000_u32.to_be_bytes());
        data[8..12].copy_from_slice(&76_u32.to_be_bytes());
        data[12..14].copy_from_slice(&1_u16.to_be_bytes());
        data[16..20].copy_from_slice(&40_u32.to_be_bytes());
        data[44..48].copy_from_slice(b"head");
        data[48..52].copy_from_slice(&64_u32.to_be_bytes());
        data[52..56].copy_from_slice(&12_u32.to_be_bytes());
        data[56..60].copy_from_slice(&12_u32.to_be_bytes());
        data
    }
    #[test]
    fn rejects_bad_headers_and_inflated_allocations_before_decoding() {
        assert!(decode(&[]).is_none());
        assert!(decode(b"not a font").is_none());
        let mut data = minimal();
        data[16..20].copy_from_slice(&u32::MAX.to_be_bytes());
        assert!(decode(&data).is_none());
        let mut data = minimal();
        data[56..60].copy_from_slice(&u32::MAX.to_be_bytes());
        assert!(decode(&data).is_none());
        let mut data = minimal();
        data[48..52].copy_from_slice(&u32::MAX.to_be_bytes());
        assert!(decode(&data).is_none());
    }
    #[test]
    fn restores_sfnt_directory_and_checksum_from_an_uncompressed_woff_table() {
        let output = decode(&minimal()).unwrap();
        assert_eq!(output.len(), 40);
        assert_eq!(&output[..4], &[0, 1, 0, 0]);
        assert_eq!(&output[12..16], b"head");
        let checksum = output.chunks_exact(4).fold(0_u32, |sum, bytes| {
            sum.wrapping_add(u32::from_be_bytes(bytes.try_into().unwrap()))
        });
        assert_eq!(checksum, 0xb1b0_afba);
    }
    #[test]
    fn raw_abi_returns_one_owned_slice_and_rejects_null_or_oversized_input() {
        let input = minimal();
        let mut length = 99;
        let pointer = unsafe { harbor_ios_font_decode(input.as_ptr(), input.len(), &mut length) };
        assert!(!pointer.is_null());
        assert_eq!(length, 40);
        assert_eq!(
            unsafe { std::slice::from_raw_parts(pointer, length) }[..4],
            [0, 1, 0, 0]
        );
        unsafe {
            harbor_ios_font_free(pointer, length);
        }
        assert!(unsafe { harbor_ios_font_decode(ptr::null(), 44, &mut length) }.is_null());
        assert_eq!(length, 0);
        assert!(
            unsafe { harbor_ios_font_decode(input.as_ptr(), MAX_INPUT + 1, &mut length) }.is_null()
        );
        assert!(
            unsafe { harbor_ios_font_decode(input.as_ptr(), input.len(), ptr::null_mut()) }
                .is_null()
        );
        unsafe {
            harbor_ios_font_free(ptr::null_mut(), 0);
        }
    }

    #[test]
    fn decodes_the_owned_actual_woff_font_and_keeps_sfnt_table_data() {
        let input = include_bytes!("../../ios/HarborTests/Fixtures/owned-reader-woff.woff");
        let output = decode(input).unwrap();
        assert_eq!(&output[..4], &[0, 1, 0, 0]);
        assert_eq!(u16_at(&output, 4), Some(10));
        assert!(output.windows(4).any(|value| value == b"glyf"));
        assert!(output.windows(4).any(|value| value == b"hmtx"));
    }

    #[test]
    fn decodes_the_owned_woff2_with_glyf_loca_and_hmtx_transformations() {
        let input = include_bytes!("../../ios/HarborTests/Fixtures/owned-reader-woff2.woff2");
        let output = decode(input).unwrap();
        assert_eq!(&output[..4], &[0, 1, 0, 0]);
        assert_eq!(u16_at(&output, 4), Some(10));
        let checksum = output.chunks(4).fold(0_u32, |sum, bytes| {
            let mut value = [0; 4];
            value[..bytes.len()].copy_from_slice(bytes);
            sum.wrapping_add(u32::from_be_bytes(value))
        });
        assert_eq!(checksum, 0xb1b0_afba);
    }
}
