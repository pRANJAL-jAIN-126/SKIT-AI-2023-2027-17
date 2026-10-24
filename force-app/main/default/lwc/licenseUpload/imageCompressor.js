/**
 * Client-side image compression for licence uploads.
 * Scales the longest side down to MAX_DIMENSION, re-encodes as JPEG and lowers
 * quality step by step until the payload is <= MAX_BYTES. Rejects otherwise.
 */
export const MAX_DIMENSION = 1600;
export const MAX_BYTES = 3 * 1024 * 1024;
const QUALITY_STEPS = [0.92, 0.85, 0.75, 0.65, 0.55, 0.45, 0.35];
const ALLOWED_TYPES = ['image/jpeg', 'image/jpg', 'image/png'];
const ALLOWED_EXT = /\.(jpe?g|png)$/i;

export class CompressionError extends Error {}

export function isAllowedImage(file) {
    if (!file) {
        return false;
    }
    return ALLOWED_TYPES.includes((file.type || '').toLowerCase()) || ALLOWED_EXT.test(file.name || '');
}

/** Size in bytes of the binary behind a base64 string (no data: prefix). */
export function base64Size(base64) {
    const padding = base64.endsWith('==') ? 2 : base64.endsWith('=') ? 1 : 0;
    return Math.floor((base64.length * 3) / 4) - padding;
}

/** Strips the "data:...;base64," prefix. */
export function stripDataUrl(dataUrl) {
    const idx = dataUrl.indexOf(',');
    return idx >= 0 ? dataUrl.substring(idx + 1) : dataUrl;
}

function readAsDataUrl(file) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result);
        reader.onerror = () => reject(new CompressionError('We could not read that file. Please choose another photo.'));
        reader.readAsDataURL(file);
    });
}

function loadImage(src) {
    return new Promise((resolve, reject) => {
        const img = new Image();
        img.onload = () => resolve(img);
        img.onerror = () => reject(new CompressionError('That file does not look like a valid JPG or PNG image.'));
        img.src = src;
    });
}

/**
 * Compresses the given File.
 * @returns {Promise<{ base64Data: string, fileName: string, bytes: number }>}
 */
export async function compressImage(file) {
    if (!isAllowedImage(file)) {
        throw new CompressionError('Please upload a JPG or PNG photo of your licence.');
    }
    const dataUrl = await readAsDataUrl(file);
    const img = await loadImage(dataUrl);

    const longest = Math.max(img.naturalWidth || img.width, img.naturalHeight || img.height) || 1;
    const scale = Math.min(1, MAX_DIMENSION / longest);
    const width = Math.max(1, Math.round((img.naturalWidth || img.width) * scale));
    const height = Math.max(1, Math.round((img.naturalHeight || img.height) * scale));

    const canvas = document.createElement('canvas');
    canvas.width = width;
    canvas.height = height;
    const ctx = canvas.getContext('2d');
    if (!ctx) {
        throw new CompressionError('Your browser could not process the image. Please try another browser.');
    }
    // White background so transparent PNGs do not turn black as JPEG.
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, width, height);
    ctx.drawImage(img, 0, 0, width, height);

    const baseName = (file.name || 'licence').replace(/\.[^.]+$/, '') || 'licence';
    for (const quality of QUALITY_STEPS) {
        const base64Data = stripDataUrl(canvas.toDataURL('image/jpeg', quality));
        const bytes = base64Size(base64Data);
        if (bytes <= MAX_BYTES) {
            return { base64Data, fileName: `${baseName}.jpg`, bytes };
        }
    }
    throw new CompressionError('This photo is too large even after compression (max 3 MB). Please take a smaller photo.');
}