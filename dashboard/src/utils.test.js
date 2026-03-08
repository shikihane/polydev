import { describe, it, expect, vi } from 'vitest';
import { timeAgo } from './utils.js';

describe('timeAgo', () => {
  it('returns empty string for falsy input', () => {
    expect(timeAgo('')).toBe('');
    expect(timeAgo(null)).toBe('');
    expect(timeAgo(undefined)).toBe('');
  });

  it('returns "just now" for recent timestamps', () => {
    const now = new Date().toISOString();
    expect(timeAgo(now)).toBe('just now');
  });

  it('returns "just now" for future timestamps (clock skew)', () => {
    const future = new Date(Date.now() + 60000).toISOString();
    expect(timeAgo(future)).toBe('just now');
  });

  it('returns minutes ago', () => {
    const fiveMinAgo = new Date(Date.now() - 5 * 60000).toISOString();
    expect(timeAgo(fiveMinAgo)).toBe('5m ago');
  });

  it('returns hours and minutes ago', () => {
    const twoHoursAgo = new Date(Date.now() - 2.5 * 3600000).toISOString();
    expect(timeAgo(twoHoursAgo)).toBe('2h 30m ago');
  });

  it('returns days ago', () => {
    const twoDaysAgo = new Date(Date.now() - 48 * 3600000).toISOString();
    expect(timeAgo(twoDaysAgo)).toBe('2d ago');
  });
});
