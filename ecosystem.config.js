module.exports = {
  apps: [
    {
      name: 'backend',
      cwd: './apps/backend',
      script: 'pnpm',
      args: 'start',
      env: {
        PORT: 3000
      }
    },
    {
      name: 'frontend',
      cwd: './apps/frontend',
      script: 'pnpm',
      args: 'start'
    },
    {
      name: 'orchestrator',
      cwd: './apps/orchestrator',
      script: 'pnpm',
      args: 'start'
    }
  ]
};
