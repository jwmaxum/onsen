import type { NextConfig } from 'next';

const config: NextConfig = {
  poweredByHeader: false,
  async redirects() {
    return [
      { source: '/', destination: '/ko/onsen', permanent: false },
      { source: '/:locale(ko|ja|en|zh-Hans)', destination: '/:locale/onsen', permanent: false },
    ];
  },
};

export default config;
