export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'scope-enum': [1, 'always', ['notch', 'ui', 'shelf', 'clipboard', 'music', 'lyrics', 'prayer', 'today', 'controls', 'tools', 'settings', 'build', 'docs', 'deps']],
  },
};
