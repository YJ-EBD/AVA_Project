package com.ava.backend.calendar;

enum CalendarEventStatus {
	SCHEDULED,
	IN_PROGRESS,
	COMPLETED,
	CANCELLED,
	POSTPONED,
	ON_HOLD
}

enum CalendarMeetingStatus {
	RESERVED,
	BEFORE_START,
	IN_MEETING,
	ENDED,
	MINUTES_READY,
	FOLLOW_UP_CREATED
}

enum CalendarVisibility {
	PRIVATE,
	ATTENDEES,
	TEAM,
	DEPARTMENT,
	COMPANY,
	ADMIN
}

enum CalendarDetailVisibility {
	FULL,
	TITLE_ONLY,
	BUSY_ONLY,
	TIME_ONLY,
	PRIVATE
}

enum CalendarAttendeeStatus {
	ACCEPTED,
	DECLINED,
	TENTATIVE,
	PENDING
}

enum CalendarReminderType {
	IN_APP,
	PUSH,
	DESKTOP,
	CHAT
}

enum CalendarReminderTargetType {
	OWNER,
	ATTENDEE,
	CHAT_ROOM
}

enum CalendarRecurrenceType {
	NONE,
	DAILY,
	WEEKLY,
	MONTHLY,
	YEARLY,
	WEEKDAYS,
	CUSTOM_DAYS,
	MONTHLY_DAY,
	CUSTOM
}

enum CalendarRecurrenceEndType {
	NEVER,
	UNTIL_DATE,
	COUNT
}

enum CalendarFileSourceType {
	NAS,
	LOCAL_UPLOAD,
	CHAT_ATTACHMENT
}

enum CalendarCategoryScope {
	USER,
	TEAM,
	DEPARTMENT,
	COMPANY,
	SYSTEM
}
