'use client';

import { useState } from 'react';
import { Copy } from 'lucide-react';

export function CopyAddress({ address, label, copied, failed }: { address: string; label: string; copied: string; failed: string }) {
  const [status, setStatus] = useState('');
  async function copy() {
    try { await navigator.clipboard.writeText(address); setStatus(copied); }
    catch { setStatus(failed); }
  }
  return <div className="copy-control"><button type="button" className="button button-outline" onClick={copy}>
    <Copy size={16} aria-hidden="true" />{label}
  </button><span role="status">{status}</span></div>;
}
