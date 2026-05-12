import 'package:flutter/material.dart';

import '../domain/messenger_models.dart';

const selfProfile = PersonProfile(
  name: '장유종',
  email: 'amos5105@naver.com',
  color: Color(0xFF7AA06A),
  status: '온라인',
);

const updatedUsers = [
  PersonProfile(name: '메롱이', color: Color(0xFF9C8E82), status: '온라인'),
  PersonProfile(name: '아방이', color: Color(0xFFA9BDF1), status: '백그라운드'),
  PersonProfile(name: '서플이', color: Color(0xFF92D5E2), status: '자리비움'),
  PersonProfile(name: '컨트릭', color: Color(0xFFA5C0EC), status: '온라인'),
  PersonProfile(name: '하이옹', color: Color(0xFF6796A7), status: '오프라인'),
];

const koreanDevelopmentUsers = [selfProfile];

const raUsers = [
  PersonProfile(name: '김라온', color: Color(0xFF8FC7D5), status: '온라인'),
  PersonProfile(name: '박도윤', color: Color(0xFFA6C6EE), status: '백그라운드'),
  PersonProfile(name: '이서진', color: Color(0xFFDDE8A5), status: '자리비움'),
  PersonProfile(name: '최민준', color: Color(0xFF9FB2D9), status: '오프라인'),
  PersonProfile(name: '정시우', color: Color(0xFF7DB3D7), status: '온라인'),
  PersonProfile(name: '한유찬', color: Color(0xFFE2B28D), status: '온라인'),
  PersonProfile(name: '문하준', color: Color(0xFFB6A4E8), status: '백그라운드'),
  PersonProfile(name: '오지후', color: Color(0xFF92D5E2), status: '자리비움'),
  PersonProfile(name: '윤태오', color: Color(0xFFAFC2EF), status: '온라인'),
  PersonProfile(name: '서이준', color: Color(0xFFD8DEA2), status: '오프라인'),
  PersonProfile(name: '강민재', color: Color(0xFF8EB6DD), status: '온라인'),
  PersonProfile(name: '배수민', color: Color(0xFF9BC9EE), status: '백그라운드'),
];

const researchUsers = [
  PersonProfile(name: '강현우', color: Color(0xFF8EB6DD), status: '온라인'),
  PersonProfile(name: '김태연', color: Color(0xFFDBE4A4), status: '백그라운드'),
  PersonProfile(name: '박서아', color: Color(0xFFA6C6EE), status: '자리비움'),
  PersonProfile(name: '이준호', color: Color(0xFF7DB3D7), status: '온라인'),
  PersonProfile(name: '최유나', color: Color(0xFFE2B28D), status: '오프라인'),
  PersonProfile(name: '정다은', color: Color(0xFFB6A4E8), status: '온라인'),
  PersonProfile(name: '한지민', color: Color(0xFF92D5E2), status: '백그라운드'),
  PersonProfile(name: '오세훈', color: Color(0xFFAFC2EF), status: '온라인'),
  PersonProfile(name: '윤가온', color: Color(0xFFD8DEA2), status: '자리비움'),
  PersonProfile(name: '송민서', color: Color(0xFF9C8E82), status: '온라인'),
  PersonProfile(name: '임도현', color: Color(0xFF6796A7), status: '오프라인'),
];

const allStaffUsers = [
  selfProfile,
  PersonProfile(name: '김민성', color: Color(0xFF8FC7D5), status: '온라인'),
  PersonProfile(name: '박지아', color: Color(0xFFA6C6EE), status: '백그라운드'),
  PersonProfile(name: '이하람', color: Color(0xFFDDE8A5), status: '온라인'),
  PersonProfile(name: '최연우', color: Color(0xFF9FB2D9), status: '오프라인'),
  PersonProfile(name: '정우진', color: Color(0xFF7DB3D7), status: '자리비움'),
  PersonProfile(name: '한소율', color: Color(0xFFE2B28D), status: '온라인'),
  PersonProfile(name: '문도겸', color: Color(0xFFB6A4E8), status: '온라인'),
  PersonProfile(name: '오나래', color: Color(0xFF92D5E2), status: '백그라운드'),
  PersonProfile(name: '윤하린', color: Color(0xFFAFC2EF), status: '온라인'),
  PersonProfile(name: '서유준', color: Color(0xFFD8DEA2), status: '자리비움'),
  PersonProfile(name: '강다온', color: Color(0xFF8EB6DD), status: '온라인'),
  PersonProfile(name: '배하은', color: Color(0xFF9BC9EE), status: '백그라운드'),
  PersonProfile(name: '노시현', color: Color(0xFFDBE4A4), status: '온라인'),
  PersonProfile(name: '차유빈', color: Color(0xFF9C8E82), status: '오프라인'),
  PersonProfile(name: '임서준', color: Color(0xFF6796A7), status: '온라인'),
  PersonProfile(name: '조민규', color: Color(0xFFA5C0EC), status: '자리비움'),
  PersonProfile(name: '백예린', color: Color(0xFF7AA06A), status: '온라인'),
  PersonProfile(name: '남건우', color: Color(0xFFE2B28D), status: '백그라운드'),
  PersonProfile(name: '신아린', color: Color(0xFF8FC7D5), status: '온라인'),
];

const designUsers = [
  PersonProfile(name: '홍예준', color: Color(0xFFB6A4E8), status: '온라인'),
  PersonProfile(name: '민서현', color: Color(0xFF92D5E2), status: '백그라운드'),
  PersonProfile(name: '고하늘', color: Color(0xFFAFC2EF), status: '온라인'),
  PersonProfile(name: '류채원', color: Color(0xFFD8DEA2), status: '자리비움'),
  PersonProfile(name: '진태민', color: Color(0xFF8EB6DD), status: '오프라인'),
  PersonProfile(name: '서나윤', color: Color(0xFF9BC9EE), status: '온라인'),
  PersonProfile(name: '권유리', color: Color(0xFFDBE4A4), status: '백그라운드'),
  PersonProfile(name: '마지호', color: Color(0xFF9C8E82), status: '온라인'),
  PersonProfile(name: '최루아', color: Color(0xFF6796A7), status: '자리비움'),
];

const logisticsUsers = [
  PersonProfile(name: '강입고', color: Color(0xFF8FC7D5), status: '온라인'),
  PersonProfile(name: '김출고', color: Color(0xFFA6C6EE), status: '온라인'),
  PersonProfile(name: '박재고', color: Color(0xFFDDE8A5), status: '백그라운드'),
  PersonProfile(name: '이검수', color: Color(0xFF9FB2D9), status: '자리비움'),
  PersonProfile(name: '최포장', color: Color(0xFF7DB3D7), status: '온라인'),
  PersonProfile(name: '정상차', color: Color(0xFFE2B28D), status: '오프라인'),
  PersonProfile(name: '한운송', color: Color(0xFFB6A4E8), status: '온라인'),
  PersonProfile(name: '문배차', color: Color(0xFF92D5E2), status: '백그라운드'),
  PersonProfile(name: '오하역', color: Color(0xFFAFC2EF), status: '온라인'),
  PersonProfile(name: '윤검품', color: Color(0xFFD8DEA2), status: '자리비움'),
  PersonProfile(name: '서보관', color: Color(0xFF8EB6DD), status: '온라인'),
  PersonProfile(name: '임입하', color: Color(0xFF9BC9EE), status: '온라인'),
  PersonProfile(name: '조출하', color: Color(0xFFDBE4A4), status: '오프라인'),
  PersonProfile(name: '백분류', color: Color(0xFF9C8E82), status: '온라인'),
  PersonProfile(name: '남적재', color: Color(0xFF6796A7), status: '백그라운드'),
];

const personalChatUsers = [
  PersonProfile(name: '김민재 대리', color: Color(0xFF8FC7D5), status: '온라인'),
  PersonProfile(name: '박서연 주임', color: Color(0xFFA6C6EE), status: '자리비움'),
  PersonProfile(name: '이도현 책임', color: Color(0xFFDDE8A5), status: '온라인'),
  PersonProfile(name: '최하린 매니저', color: Color(0xFF9FB2D9), status: '오프라인'),
  PersonProfile(name: '정우성 과장', color: Color(0xFF7DB3D7), status: '백그라운드'),
  PersonProfile(name: '한지우 연구원', color: Color(0xFFE2B28D), status: '온라인'),
  PersonProfile(name: '오나래 디자이너', color: Color(0xFFB6A4E8), status: '자리비움'),
  PersonProfile(name: '강수진 PM', color: Color(0xFF92D5E2), status: '온라인'),
  PersonProfile(name: '윤태호 선임', color: Color(0xFFAFC2EF), status: '백그라운드'),
  PersonProfile(name: '서하늘 사원', color: Color(0xFFD8DEA2), status: '온라인'),
];

final userGroups = [
  UserGroup(title: '한국 개발부', users: koreanDevelopmentUsers),
  UserGroup(
    title: 'RA 팀',
    users: [raUsers[0], raUsers[1], raUsers[2], raUsers[3]],
  ),
  UserGroup(
    title: '영업부',
    users: [
      PersonProfile(name: '서지훈', color: Color(0xFFB6A4E8), status: '온라인'),
      PersonProfile(name: '오세영', color: Color(0xFF92D5E2), status: '백그라운드'),
      PersonProfile(name: '정다빈', color: Color(0xFFE2B28D), status: '온라인'),
      PersonProfile(name: '문태양', color: Color(0xFF7DB3D7), status: '자리비움'),
      PersonProfile(name: '윤유진', color: Color(0xFFAFC2EF), status: '오프라인'),
    ],
  ),
  UserGroup(
    title: '생산기술',
    users: [
      PersonProfile(name: '강현아', color: Color(0xFF8EB6DD), status: '온라인'),
      PersonProfile(name: '배수미', color: Color(0xFFD8DEA2), status: '백그라운드'),
      PersonProfile(name: '오하준', color: Color(0xFF9BC9EE), status: '자리비움'),
    ],
  ),
];

final chatRooms = [
  ChatRoom(
    id: 'ra-team',
    title: 'RA팀',
    preview: '인증 일정표 업데이트해서 공유했습니다.',
    time: '오후 1:08',
    members: raUsers,
    unreadCount: 4,
    isPinned: true,
  ),
  ChatRoom(
    id: 'research-lab',
    title: '연구소',
    preview: 'Qwen 테스트 로그와 벤치 결과 확인 부탁드립니다.',
    time: '오후 12:42',
    members: researchUsers,
  ),
  ChatRoom(
    id: 'all-staff',
    title: '전직원',
    preview: '오늘 오후 5시 전사 공지 확인해주세요.',
    time: '오전 9:10',
    members: allStaffUsers,
  ),
  ChatRoom(
    id: 'design-team',
    title: '디자인팀',
    preview: '메신저 아이콘 시안 2차 업로드했습니다.',
    time: '오후 2:16',
    members: designUsers,
  ),
  ChatRoom(
    id: 'logistics-room',
    title: '입출고방',
    preview: '오전 입고분 검수 완료, 출고 리스트 확인 중입니다.',
    time: '오전 8:58',
    members: logisticsUsers,
  ),
  ChatRoom(
    id: 'kim-minjae',
    title: '김민재 대리',
    preview: '회의록 정리해서 드라이브에 올려두었습니다.',
    time: '오후 12:05',
    members: [personalChatUsers[0]],
    unreadCount: 2,
  ),
  ChatRoom(
    id: 'park-seoyeon',
    title: '박서연 주임',
    preview: '견적서 수정본 확인 부탁드립니다.',
    time: '오전 9:46',
    members: [personalChatUsers[1]],
  ),
  ChatRoom(
    id: 'lee-dohyun',
    title: '이도현 책임',
    preview: 'API 명세는 오늘 중으로 업데이트하겠습니다.',
    time: '어제',
    members: [personalChatUsers[2]],
  ),
  ChatRoom(
    id: 'choi-harin',
    title: '최하린 매니저',
    preview: '이번 주 배포 일정 다시 조율해볼게요.',
    time: '어제',
    members: [personalChatUsers[3]],
  ),
  ChatRoom(
    id: 'jung-woosung',
    title: '정우성 과장',
    preview: '서버 장비 입고 일정 확인했습니다.',
    time: '월요일',
    members: [personalChatUsers[4]],
  ),
  ChatRoom(
    id: 'han-jiwoo',
    title: '한지우 연구원',
    preview: '테스트 샘플 데이터 추가해두었습니다.',
    time: '월요일',
    members: [personalChatUsers[5]],
  ),
  ChatRoom(
    id: 'oh-narae',
    title: '오나래 디자이너',
    preview: '메인 컬러는 AVA 블루 쪽으로 맞춰볼게요.',
    time: '일요일',
    members: [personalChatUsers[6]],
  ),
  ChatRoom(
    id: 'kang-sujin',
    title: '강수진 PM',
    preview: '다음 스프린트 작업 범위 확인했습니다.',
    time: '토요일',
    members: [personalChatUsers[7]],
  ),
  ChatRoom(
    id: 'yoon-taeho',
    title: '윤태호 선임',
    preview: '장비 발주 품목은 오후에 다시 보내드릴게요.',
    time: '금요일',
    members: [personalChatUsers[8]],
  ),
  ChatRoom(
    id: 'seo-haneul',
    title: '서하늘 사원',
    preview: '출근 체크 오류는 수정 완료했습니다.',
    time: '금요일',
    members: [personalChatUsers[9]],
  ),
];

ChatRoom directChatRoomFor(PersonProfile user) {
  return ChatRoom(
    id: 'direct-${user.identityKey}',
    title: user.name,
    preview: '${user.name}님과 1:1 채팅을 시작했습니다.',
    time: '방금',
    members: [user],
    participantCount: 2,
    isDraft: true,
  );
}

ChatRoom selfChatRoomFor(PersonProfile user) {
  return ChatRoom(
    id: 'self-${user.identityKey}',
    title: '\uB098\uC640\uC758 \uCC44\uD305',
    preview: '',
    time: '',
    members: [user],
    participantCount: 1,
    isDraft: true,
  );
}

List<ChatMessage> messagesFor(ChatRoom room) {
  if (room.isDirectChat || room.isSelfChat) {
    return const [];
  }

  return [
    ChatMessage(
      sender: room.members.first,
      text: '${room.title} 채팅방에 입장했습니다.',
      time: '오전 10:18',
      isMine: false,
    ),
    ChatMessage(
      sender: selfProfile,
      text: '확인했습니다. 관련 자료 정리해서 공유드릴게요.',
      time: '오전 10:21',
      isMine: true,
    ),
    ChatMessage(
      sender: room.members.first,
      text: room.preview,
      time: room.time,
      isMine: false,
    ),
  ];
}
