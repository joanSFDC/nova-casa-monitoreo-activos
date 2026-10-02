const { jestConfig } = require("@salesforce/sfdx-lwc-jest/config");

module.exports = {
  ...jestConfig,
  moduleNameMapper: {
    ...jestConfig.moduleNameMapper,
    "^lightning/modal$": "<rootDir>/jest-mocks/lightning/modal"
  },
  modulePathIgnorePatterns: ["<rootDir>/.localdevserver"]
};
