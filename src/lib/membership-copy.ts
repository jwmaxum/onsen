import { locales, type Locale } from './catalog-query';

const copy = {
  account: ['회원 계정', 'アカウント', 'Account', '会员账户'],
  articles: ['온천 소식', '温泉だより', 'Onsen news', '温泉资讯'],
  admin: ['콘텐츠 관리', 'コンテンツ管理', 'Manage content', '内容管理'],
  signIn: ['로그인', 'ログイン', 'Sign in', '登录'],
  signUp: ['회원가입', '新規登録', 'Create an account', '注册'],
  signOut: ['로그아웃', 'ログアウト', 'Sign out', '退出登录'],
  email: ['이메일', 'メールアドレス', 'Email', '电子邮件'],
  password: ['비밀번호', 'パスワード', 'Password', '密码'],
  name: ['이름', '氏名', 'Name', '姓名'],
  phone: ['전화번호', '電話番号', 'Phone number', '电话号码'],
  save: ['저장', '保存', 'Save', '保存'],
  saved: ['저장했습니다.', '保存しました。', 'Saved.', '已保存。'],
  loading: ['불러오는 중…', '読み込み中…', 'Loading…', '正在加载…'],
  unavailable: ['지금은 연결할 수 없습니다. 잠시 후 다시 시도하세요.', '接続できません。しばらくしてから再試行してください。', 'Connection unavailable. Try again in a moment.', '暂时无法连接，请稍后重试。'],
  badLogin: ['이메일 또는 비밀번호를 확인하세요.', 'メールアドレスまたはパスワードを確認してください。', 'Check your email and password.', '请检查电子邮件地址和密码。'],
  badSignup: ['가입 정보를 확인해 주세요. 이미 가입하셨다면 로그인하세요.', '登録情報を確認してください。登録済みの場合はログインしてください。', 'Check your details. If you already have an account, sign in.', '请检查注册信息。如已有账号，请登录。'],
  badProfile: ['이름과 전화번호를 확인해 주세요.', '氏名と電話番号を確認してください。', 'Check your name and phone number.', '请检查姓名和电话号码。'],
  profileNotice: ['이름과 전화번호는 비공개 회원 정보로 저장됩니다.', '氏名と電話番号は非公開の会員情報として保存されます。', 'Your name and phone number are saved in your private member profile.', '姓名和电话号码保存在您的私密会员资料中。'],
  profilePending: ['회원 정보를 저장해 가입을 마무리하세요.', '会員情報を保存して登録を完了してください。', 'Save your profile to finish signing up.', '请保存会员资料以完成注册。'],
  verifyEmail: ['이메일을 인증할 수 있습니다.', 'メールアドレスを確認できます。', 'You can verify your email address.', '您可以验证电子邮件地址。'],
  sendVerification: ['인증 메일 보내기', '確認メールを送信', 'Send verification email', '发送验证邮件'],
  checkVerification: ['인증 확인', '確認状況を更新', 'Check verification', '检查验证状态'],
  verificationSent: ['인증 메일을 보냈습니다. 메일의 링크를 연 뒤 인증을 확인하세요.', '確認メールを送信しました。リンクを開いた後、確認状況を更新してください。', 'Verification email sent. Open its link, then check your verification here.', '已发送验证邮件。打开邮件中的链接，然后在此检查验证状态。'],
  verificationPending: ['콘텐츠를 관리하려면 관리자 이메일을 인증해 주세요.', 'コンテンツを管理するには、管理者のメールアドレスを確認してください。', 'Verify the administrator email to manage content.', '请验证管理员邮箱以管理内容。'],
  verificationComplete: ['이메일 인증이 완료되었습니다.', 'メールアドレスの確認が完了しました。', 'Email verified.', '邮箱已验证。'],
  denied: ['등록된 관리자 UID로 로그인해 주세요.', '登録済みの管理者アカウントでログインしてください。', 'Sign in with the registered admin account.', '请使用已登记的管理员账号登录。'],
  newArticle: ['새 콘텐츠', '新規コンテンツ', 'New content', '新建内容'],
  edit: ['수정', '編集', 'Edit', '编辑'],
  locale: ['콘텐츠 언어', 'コンテンツの言語', 'Content language', '内容语言'],
  title: ['제목', 'タイトル', 'Title', '标题'],
  body: ['본문', '本文', 'Body', '正文'],
  published: ['공개', '公開', 'Published', '已发布'],
  publish: ['사이트에 공개', 'サイトで公開', 'Publish on the website', '在网站上发布'],
  draft: ['초안', '下書き', 'Draft', '草稿'],
  conflict: ['이미 수정된 콘텐츠입니다. 목록에서 다시 열어 주세요.', '内容が更新されました。一覧から開き直してください。', 'This entry has changed. Reopen it from the list.', '此内容已修改，请从列表重新打开。'],
  empty: ['등록된 콘텐츠가 없습니다.', '登録されたコンテンツはありません。', 'No content yet.', '暂无内容。'],
};

export function membershipText(locale: Locale) {
  const index = locales.indexOf(locale);
  return (key: keyof typeof copy) => copy[key][index];
}
