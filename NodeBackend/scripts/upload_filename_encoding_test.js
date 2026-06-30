const { repairLatin1Utf8FileName, uploadFileName } = require('../src/utils/uploadNames');

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

const koreanName = '테스트 파일 01.txt';
const mojibakeName = Buffer.from(koreanName, 'utf8').toString('latin1');

assert(
  repairLatin1Utf8FileName(mojibakeName) === koreanName,
  'Korean filename mojibake was not repaired.'
);
assert(
  repairLatin1Utf8FileName(koreanName) === koreanName,
  'Already-valid Korean filename should not be changed.'
);
assert(
  uploadFileName({ originalname: `C:\\fakepath\\${mojibakeName}` }) === koreanName,
  'Upload filename should strip path segments and repair mojibake.'
);
assert(
  uploadFileName({ originalname: 'report.pdf' }) === 'report.pdf',
  'ASCII filenames should not be changed.'
);

console.log(JSON.stringify({ ok: true, checked: 4 }, null, 2));
