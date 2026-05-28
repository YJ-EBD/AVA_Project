enum CalendarViewMode { month, week, day, list }

class CalendarCategory {
  const CalendarCategory({
    required this.id,
    required this.name,
    required this.color,
    this.icon,
    this.scope = 'USER',
    this.defaultCategory = false,
    this.sortOrder = 0,
  });

  factory CalendarCategory.fromJson(Map<String, dynamic> json) {
    return CalendarCategory(
      id: _string(json['id']),
      name: _string(json['name'], fallback: '기타'),
      color: _string(json['color'], fallback: '#8A8F98'),
      icon: _nullableString(json['icon']),
      scope: _string(json['scope'], fallback: 'USER'),
      defaultCategory: json['defaultCategory'] as bool? ?? false,
      sortOrder: _int(json['sortOrder']) ?? 0,
    );
  }

  final String id;
  final String name;
  final String color;
  final String? icon;
  final String scope;
  final bool defaultCategory;
  final int sortOrder;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'color': color,
      'icon': icon,
      'scope': scope,
      'defaultCategory': defaultCategory,
      'sortOrder': sortOrder,
    };
  }
}

class CalendarAttendee {
  const CalendarAttendee({
    this.id,
    this.userId,
    required this.displayName,
    this.department,
    this.position,
    this.email,
    this.responseStatus = 'PENDING',
    this.responseMessage,
    this.respondedAt,
  });

  factory CalendarAttendee.fromJson(Map<String, dynamic> json) {
    return CalendarAttendee(
      id: _nullableString(json['id']),
      userId: _nullableString(json['userId']),
      displayName: _string(json['displayName'], fallback: '참석자'),
      department: _nullableString(json['department']),
      position: _nullableString(json['position']),
      email: _nullableString(json['email']),
      responseStatus: _string(json['responseStatus'], fallback: 'PENDING'),
      responseMessage: _nullableString(json['responseMessage']),
      respondedAt: _nullableDateTime(json['respondedAt']),
    );
  }

  final String? id;
  final String? userId;
  final String displayName;
  final String? department;
  final String? position;
  final String? email;
  final String responseStatus;
  final String? responseMessage;
  final DateTime? respondedAt;

  Map<String, dynamic> toRequest() {
    return {
      if (userId != null && userId!.isNotEmpty) 'userId': userId,
      'displayName': displayName,
      if (department != null && department!.isNotEmpty)
        'department': department,
      if (position != null && position!.isNotEmpty) 'position': position,
      if (email != null && email!.isNotEmpty) 'email': email,
      'responseStatus': responseStatus,
      if (responseMessage != null && responseMessage!.isNotEmpty)
        'responseMessage': responseMessage,
      if (respondedAt != null)
        'respondedAt': respondedAt!.toUtc().toIso8601String(),
    };
  }
}

class CalendarReminder {
  const CalendarReminder({
    this.id,
    required this.remindBeforeMinutes,
    this.reminderType = 'IN_APP',
    this.targetType = 'OWNER',
    this.targetId,
    this.sent = false,
  });

  factory CalendarReminder.fromJson(Map<String, dynamic> json) {
    return CalendarReminder(
      id: _nullableString(json['id']),
      remindBeforeMinutes: _int(json['remindBeforeMinutes']) ?? 10,
      reminderType: _string(json['reminderType'], fallback: 'IN_APP'),
      targetType: _string(json['targetType'], fallback: 'OWNER'),
      targetId: _nullableString(json['targetId']),
      sent: json['sent'] as bool? ?? false,
    );
  }

  final String? id;
  final int remindBeforeMinutes;
  final String reminderType;
  final String targetType;
  final String? targetId;
  final bool sent;

  Map<String, dynamic> toRequest() {
    return {
      'remindBeforeMinutes': remindBeforeMinutes,
      'reminderType': reminderType,
      'targetType': targetType,
      if (targetId != null && targetId!.isNotEmpty) 'targetId': targetId,
    };
  }
}

class CalendarRecurrence {
  const CalendarRecurrence({
    this.id,
    this.recurrenceType = 'NONE',
    this.intervalValue = 1,
    this.daysOfWeek,
    this.dayOfMonth,
    this.endType = 'NEVER',
    this.untilDate,
    this.occurrenceCount,
    this.rrule,
    this.timezone = 'Asia/Seoul',
  });

  factory CalendarRecurrence.fromJson(Map<String, dynamic> json) {
    return CalendarRecurrence(
      id: _nullableString(json['id']),
      recurrenceType: _string(json['recurrenceType'], fallback: 'NONE'),
      intervalValue: _int(json['intervalValue']) ?? 1,
      daysOfWeek: _nullableString(json['daysOfWeek']),
      dayOfMonth: _int(json['dayOfMonth']),
      endType: _string(json['endType'], fallback: 'NEVER'),
      untilDate: _nullableDate(json['untilDate']),
      occurrenceCount: _int(json['occurrenceCount']),
      rrule: _nullableString(json['rrule']),
      timezone: _string(json['timezone'], fallback: 'Asia/Seoul'),
    );
  }

  final String? id;
  final String recurrenceType;
  final int intervalValue;
  final String? daysOfWeek;
  final int? dayOfMonth;
  final String endType;
  final DateTime? untilDate;
  final int? occurrenceCount;
  final String? rrule;
  final String timezone;

  bool get isRepeating => recurrenceType != 'NONE';

  Map<String, dynamic> toRequest() {
    return {
      'recurrenceType': recurrenceType,
      'intervalValue': intervalValue,
      if (daysOfWeek != null && daysOfWeek!.isNotEmpty)
        'daysOfWeek': daysOfWeek,
      if (dayOfMonth != null) 'dayOfMonth': dayOfMonth,
      'endType': endType,
      if (untilDate != null) 'untilDate': _dateOnly(untilDate!),
      if (occurrenceCount != null) 'occurrenceCount': occurrenceCount,
      if (rrule != null && rrule!.isNotEmpty) 'rrule': rrule,
      'timezone': timezone,
    };
  }
}

class CalendarFileLink {
  const CalendarFileLink({
    this.id,
    this.fileId,
    required this.fileName,
    this.filePath,
    this.fileType,
    this.fileSize,
    this.sourceType = 'NAS',
  });

  factory CalendarFileLink.fromJson(Map<String, dynamic> json) {
    return CalendarFileLink(
      id: _nullableString(json['id']),
      fileId: _nullableString(json['fileId']),
      fileName: _string(json['fileName'], fallback: '파일'),
      filePath: _nullableString(json['filePath']),
      fileType: _nullableString(json['fileType']),
      fileSize: _int(json['fileSize']),
      sourceType: _string(json['sourceType'], fallback: 'NAS'),
    );
  }

  final String? id;
  final String? fileId;
  final String fileName;
  final String? filePath;
  final String? fileType;
  final int? fileSize;
  final String sourceType;

  Map<String, dynamic> toRequest() {
    return {
      if (fileId != null && fileId!.isNotEmpty) 'fileId': fileId,
      'fileName': fileName,
      if (filePath != null && filePath!.isNotEmpty) 'filePath': filePath,
      if (fileType != null && fileType!.isNotEmpty) 'fileType': fileType,
      if (fileSize != null) 'fileSize': fileSize,
      'sourceType': sourceType,
    };
  }
}

class CalendarNotionLink {
  const CalendarNotionLink({
    this.id,
    this.notionPageId,
    this.notionDatabaseId,
    required this.notionTitle,
    this.notionUrl,
  });

  factory CalendarNotionLink.fromJson(Map<String, dynamic> json) {
    return CalendarNotionLink(
      id: _nullableString(json['id']),
      notionPageId: _nullableString(json['notionPageId']),
      notionDatabaseId: _nullableString(json['notionDatabaseId']),
      notionTitle: _string(json['notionTitle'], fallback: 'Notion'),
      notionUrl: _nullableString(json['notionUrl']),
    );
  }

  final String? id;
  final String? notionPageId;
  final String? notionDatabaseId;
  final String notionTitle;
  final String? notionUrl;

  Map<String, dynamic> toRequest() {
    return {
      if (notionPageId != null && notionPageId!.isNotEmpty)
        'notionPageId': notionPageId,
      if (notionDatabaseId != null && notionDatabaseId!.isNotEmpty)
        'notionDatabaseId': notionDatabaseId,
      'notionTitle': notionTitle,
      if (notionUrl != null && notionUrl!.isNotEmpty) 'notionUrl': notionUrl,
    };
  }
}

class CalendarChatLink {
  const CalendarChatLink({
    this.id,
    required this.chatRoomId,
    this.chatRoomName,
    this.sourceMessageId,
    this.sourceMessagePreview,
  });

  factory CalendarChatLink.fromJson(Map<String, dynamic> json) {
    return CalendarChatLink(
      id: _nullableString(json['id']),
      chatRoomId: _string(json['chatRoomId']),
      chatRoomName: _nullableString(json['chatRoomName']),
      sourceMessageId: _nullableString(json['sourceMessageId']),
      sourceMessagePreview: _nullableString(json['sourceMessagePreview']),
    );
  }

  final String? id;
  final String chatRoomId;
  final String? chatRoomName;
  final String? sourceMessageId;
  final String? sourceMessagePreview;

  Map<String, dynamic> toRequest() {
    return {
      'chatRoomId': chatRoomId,
      if (chatRoomName != null && chatRoomName!.isNotEmpty)
        'chatRoomName': chatRoomName,
      if (sourceMessageId != null && sourceMessageId!.isNotEmpty)
        'sourceMessageId': sourceMessageId,
      if (sourceMessagePreview != null && sourceMessagePreview!.isNotEmpty)
        'sourceMessagePreview': sourceMessagePreview,
    };
  }
}

class CalendarAzoomLink {
  const CalendarAzoomLink({
    this.id,
    this.azoomMeetingId,
    this.azoomRoomId,
    this.azoomJoinUrl,
    this.azoomRecordingId,
    this.azoomTranscriptId,
    this.azoomMinutesId,
  });

  factory CalendarAzoomLink.fromJson(Map<String, dynamic> json) {
    return CalendarAzoomLink(
      id: _nullableString(json['id']),
      azoomMeetingId: _nullableString(json['azoomMeetingId']),
      azoomRoomId: _nullableString(json['azoomRoomId']),
      azoomJoinUrl: _nullableString(json['azoomJoinUrl']),
      azoomRecordingId: _nullableString(json['azoomRecordingId']),
      azoomTranscriptId: _nullableString(json['azoomTranscriptId']),
      azoomMinutesId: _nullableString(json['azoomMinutesId']),
    );
  }

  final String? id;
  final String? azoomMeetingId;
  final String? azoomRoomId;
  final String? azoomJoinUrl;
  final String? azoomRecordingId;
  final String? azoomTranscriptId;
  final String? azoomMinutesId;

  Map<String, dynamic> toRequest() {
    return {
      if (azoomMeetingId != null && azoomMeetingId!.isNotEmpty)
        'azoomMeetingId': azoomMeetingId,
      if (azoomRoomId != null && azoomRoomId!.isNotEmpty)
        'azoomRoomId': azoomRoomId,
      if (azoomJoinUrl != null && azoomJoinUrl!.isNotEmpty)
        'azoomJoinUrl': azoomJoinUrl,
      if (azoomRecordingId != null && azoomRecordingId!.isNotEmpty)
        'azoomRecordingId': azoomRecordingId,
      if (azoomTranscriptId != null && azoomTranscriptId!.isNotEmpty)
        'azoomTranscriptId': azoomTranscriptId,
      if (azoomMinutesId != null && azoomMinutesId!.isNotEmpty)
        'azoomMinutesId': azoomMinutesId,
    };
  }
}

class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    this.description,
    required this.startAt,
    required this.endAt,
    this.occurrenceStartAt,
    this.occurrenceEndAt,
    this.allDay = false,
    this.location,
    this.categoryId,
    this.category,
    this.color,
    this.status = 'SCHEDULED',
    this.meetingStatus = 'RESERVED',
    this.visibility = 'ATTENDEES',
    this.detailVisibility = 'FULL',
    this.ownerUserId,
    this.createdBy,
    this.updatedBy,
    this.memo,
    this.projectName,
    this.attendees = const [],
    this.reminders = const [],
    this.recurrence,
    this.files = const [],
    this.notionLinks = const [],
    this.chatLinks = const [],
    this.azoomLinks = const [],
    this.createdAt,
    this.updatedAt,
  });

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    final categoryMap = (json['category'] as Map?)?.cast<String, dynamic>();
    return CalendarEvent(
      id: _string(json['id']),
      title: _string(json['title'], fallback: '새 일정'),
      description: _nullableString(json['description']),
      startAt: _dateTime(json['startAt']),
      endAt: _dateTime(json['endAt']),
      occurrenceStartAt: _nullableDateTime(json['occurrenceStartAt']),
      occurrenceEndAt: _nullableDateTime(json['occurrenceEndAt']),
      allDay: json['allDay'] as bool? ?? false,
      location: _nullableString(json['location']),
      categoryId: _nullableString(json['categoryId']),
      category: categoryMap == null
          ? null
          : CalendarCategory.fromJson(categoryMap),
      color: _nullableString(json['color']),
      status: _string(json['status'], fallback: 'SCHEDULED'),
      meetingStatus: _string(json['meetingStatus'], fallback: 'RESERVED'),
      visibility: _string(json['visibility'], fallback: 'ATTENDEES'),
      detailVisibility: _string(json['detailVisibility'], fallback: 'FULL'),
      ownerUserId: _nullableString(json['ownerUserId']),
      createdBy: _nullableString(json['createdBy']),
      updatedBy: _nullableString(json['updatedBy']),
      memo: _nullableString(json['memo']),
      projectName: _nullableString(json['projectName']),
      attendees: [
        for (final item in json['attendees'] as List? ?? const [])
          CalendarAttendee.fromJson((item as Map).cast<String, dynamic>()),
      ],
      reminders: [
        for (final item in json['reminders'] as List? ?? const [])
          CalendarReminder.fromJson((item as Map).cast<String, dynamic>()),
      ],
      recurrence: json['recurrence'] == null
          ? null
          : CalendarRecurrence.fromJson(
              (json['recurrence'] as Map).cast<String, dynamic>(),
            ),
      files: [
        for (final item in json['files'] as List? ?? const [])
          CalendarFileLink.fromJson((item as Map).cast<String, dynamic>()),
      ],
      notionLinks: [
        for (final item in json['notionLinks'] as List? ?? const [])
          CalendarNotionLink.fromJson((item as Map).cast<String, dynamic>()),
      ],
      chatLinks: [
        for (final item in json['chatLinks'] as List? ?? const [])
          CalendarChatLink.fromJson((item as Map).cast<String, dynamic>()),
      ],
      azoomLinks: [
        for (final item in json['azoomLinks'] as List? ?? const [])
          CalendarAzoomLink.fromJson((item as Map).cast<String, dynamic>()),
      ],
      createdAt: _nullableDateTime(json['createdAt']),
      updatedAt: _nullableDateTime(json['updatedAt']),
    );
  }

  final String id;
  final String title;
  final String? description;
  final DateTime startAt;
  final DateTime endAt;
  final DateTime? occurrenceStartAt;
  final DateTime? occurrenceEndAt;
  final bool allDay;
  final String? location;
  final String? categoryId;
  final CalendarCategory? category;
  final String? color;
  final String status;
  final String meetingStatus;
  final String visibility;
  final String detailVisibility;
  final String? ownerUserId;
  final String? createdBy;
  final String? updatedBy;
  final String? memo;
  final String? projectName;
  final List<CalendarAttendee> attendees;
  final List<CalendarReminder> reminders;
  final CalendarRecurrence? recurrence;
  final List<CalendarFileLink> files;
  final List<CalendarNotionLink> notionLinks;
  final List<CalendarChatLink> chatLinks;
  final List<CalendarAzoomLink> azoomLinks;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  DateTime get displayStart => occurrenceStartAt ?? startAt;
  DateTime get displayEnd => occurrenceEndAt ?? endAt;
  bool get hasAzoom => azoomLinks.isNotEmpty;
  bool get hasFiles => files.isNotEmpty;
  bool get hasNotion => notionLinks.isNotEmpty;
  bool get hasChat => chatLinks.isNotEmpty;

  String get effectiveColor => color ?? category?.color ?? '#5B7CFA';

  CalendarEvent copyWith({
    String? title,
    String? description,
    DateTime? startAt,
    DateTime? endAt,
    bool? allDay,
    String? location,
    String? categoryId,
    CalendarCategory? category,
    String? color,
    String? status,
    String? meetingStatus,
    String? visibility,
    String? detailVisibility,
    String? memo,
    String? projectName,
    List<CalendarAttendee>? attendees,
    List<CalendarReminder>? reminders,
    CalendarRecurrence? recurrence,
    List<CalendarFileLink>? files,
    List<CalendarNotionLink>? notionLinks,
    List<CalendarChatLink>? chatLinks,
    List<CalendarAzoomLink>? azoomLinks,
  }) {
    return CalendarEvent(
      id: id,
      title: title ?? this.title,
      description: description ?? this.description,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      occurrenceStartAt: occurrenceStartAt,
      occurrenceEndAt: occurrenceEndAt,
      allDay: allDay ?? this.allDay,
      location: location ?? this.location,
      categoryId: categoryId ?? this.categoryId,
      category: category ?? this.category,
      color: color ?? this.color,
      status: status ?? this.status,
      meetingStatus: meetingStatus ?? this.meetingStatus,
      visibility: visibility ?? this.visibility,
      detailVisibility: detailVisibility ?? this.detailVisibility,
      ownerUserId: ownerUserId,
      createdBy: createdBy,
      updatedBy: updatedBy,
      memo: memo ?? this.memo,
      projectName: projectName ?? this.projectName,
      attendees: attendees ?? this.attendees,
      reminders: reminders ?? this.reminders,
      recurrence: recurrence ?? this.recurrence,
      files: files ?? this.files,
      notionLinks: notionLinks ?? this.notionLinks,
      chatLinks: chatLinks ?? this.chatLinks,
      azoomLinks: azoomLinks ?? this.azoomLinks,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toRequest({
    bool ignoreConflicts = false,
    bool includeEmptyCollections = false,
  }) {
    return {
      'title': title,
      if (description != null && description!.isNotEmpty)
        'description': description,
      'startAt': startAt.toUtc().toIso8601String(),
      'endAt': endAt.toUtc().toIso8601String(),
      'allDay': allDay,
      if (location != null && location!.isNotEmpty) 'location': location,
      if (categoryId != null && categoryId!.isNotEmpty)
        'categoryId': categoryId,
      if (color != null && color!.isNotEmpty) 'color': color,
      'status': status,
      'meetingStatus': meetingStatus,
      'visibility': visibility,
      'detailVisibility': detailVisibility,
      if (memo != null && memo!.isNotEmpty) 'memo': memo,
      if (projectName != null && projectName!.isNotEmpty)
        'projectName': projectName,
      if (includeEmptyCollections || attendees.isNotEmpty)
        'attendees': attendees.map((item) => item.toRequest()).toList(),
      if (includeEmptyCollections || reminders.isNotEmpty)
        'reminders': reminders.map((item) => item.toRequest()).toList(),
      if (recurrence != null) 'recurrence': recurrence!.toRequest(),
      if (includeEmptyCollections || files.isNotEmpty)
        'files': files.map((item) => item.toRequest()).toList(),
      if (includeEmptyCollections || notionLinks.isNotEmpty)
        'notionLinks': notionLinks.map((item) => item.toRequest()).toList(),
      if (includeEmptyCollections || chatLinks.isNotEmpty)
        'chatLinks': chatLinks.map((item) => item.toRequest()).toList(),
      if (includeEmptyCollections || azoomLinks.isNotEmpty)
        'azoomLinks': azoomLinks.map((item) => item.toRequest()).toList(),
      'ignoreConflicts': ignoreConflicts,
      'source': 'APP',
    };
  }
}

class CalendarConflict {
  const CalendarConflict({
    required this.eventId,
    required this.title,
    required this.startAt,
    required this.endAt,
    required this.reason,
    this.ownerName,
  });

  factory CalendarConflict.fromJson(Map<String, dynamic> json) {
    return CalendarConflict(
      eventId: _string(json['eventId']),
      title: _string(json['title'], fallback: '충돌 일정'),
      startAt: _dateTime(json['startAt']),
      endAt: _dateTime(json['endAt']),
      reason: _string(json['reason'], fallback: '시간 겹침'),
      ownerName: _nullableString(json['ownerName']),
    );
  }

  final String eventId;
  final String title;
  final DateTime startAt;
  final DateTime endAt;
  final String reason;
  final String? ownerName;
}

class AvailabilitySuggestion {
  const AvailabilitySuggestion({
    required this.startAt,
    required this.endAt,
    required this.score,
    this.attendeeConflicts = const [],
  });

  factory AvailabilitySuggestion.fromJson(Map<String, dynamic> json) {
    return AvailabilitySuggestion(
      startAt: _dateTime(json['startAt']),
      endAt: _dateTime(json['endAt']),
      score: _int(json['score']) ?? 0,
      attendeeConflicts: [
        for (final item in json['attendeeConflicts'] as List? ?? const [])
          CalendarConflict.fromJson((item as Map).cast<String, dynamic>()),
      ],
    );
  }

  final DateTime startAt;
  final DateTime endAt;
  final int score;
  final List<CalendarConflict> attendeeConflicts;
}

String calendarStatusLabel(String value) {
  return switch (value) {
    'IN_PROGRESS' => '진행 중',
    'COMPLETED' => '완료',
    'CANCELLED' => '취소',
    'POSTPONED' => '연기',
    'ON_HOLD' => '보류',
    _ => '예정',
  };
}

String calendarVisibilityLabel(String value) {
  return switch (value) {
    'PRIVATE' => '나만 보기',
    'TEAM' => '팀원 보기',
    'DEPARTMENT' => '부서 보기',
    'COMPANY' => '회사 전체 보기',
    'ADMIN' => '관리자만 보기',
    _ => '참석자만 보기',
  };
}

String calendarRecurrenceLabel(String value) {
  return switch (value) {
    'DAILY' => '매일',
    'WEEKLY' => '매주',
    'MONTHLY' => '매월',
    'YEARLY' => '매년',
    'WEEKDAYS' => '평일',
    'CUSTOM_DAYS' => '특정 요일',
    'MONTHLY_DAY' => '매월 특정 날짜',
    'CUSTOM' => '사용자 지정',
    _ => '반복 없음',
  };
}

String calendarAttendeeStatusLabel(String value) {
  return switch (value) {
    'ACCEPTED' => '참석',
    'DECLINED' => '불참',
    'TENTATIVE' => '미정',
    _ => '응답 대기',
  };
}

String _string(Object? value, {String fallback = ''}) {
  if (value == null) {
    return fallback;
  }
  final text = value.toString();
  return text.isEmpty ? fallback : text;
}

String? _nullableString(Object? value) {
  final text = _string(value);
  return text.isEmpty ? null : text;
}

int? _int(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '');
}

DateTime _dateTime(Object? value) {
  final parsed = _nullableDateTime(value);
  return parsed ?? DateTime.now();
}

DateTime? _nullableDateTime(Object? value) {
  if (value == null) {
    return null;
  }
  return DateTime.tryParse(value.toString())?.toLocal();
}

DateTime? _nullableDate(Object? value) {
  if (value == null) {
    return null;
  }
  final parsed = DateTime.tryParse(value.toString());
  if (parsed == null) {
    return null;
  }
  return DateTime(parsed.year, parsed.month, parsed.day);
}

String _dateOnly(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
