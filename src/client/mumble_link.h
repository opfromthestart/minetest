// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later

#pragma once

#include "irr_v3d.h"
#include <string>
#include <cstdint>

class MumbleLink {
public:
	MumbleLink();
	~MumbleLink();

	MumbleLink(const MumbleLink&) = delete;
	MumbleLink& operator=(const MumbleLink&) = delete;

	void init();
	void setContext(const std::string &context);
	void setIdentity(const std::string &identity);
	void update(v3f camera_pos, v3f camera_dir, v3f camera_up,
		    v3f player_pos, v3f player_dir, v3f player_up);
	bool isConnected() const { return m_connected; }

private:
	struct LinkedMem {
		uint32_t ui_version;
		uint32_t ui_tick;
		float avatar_position[3];
		float avatar_front[3];
		float avatar_top[3];
		wchar_t name[256];
		float camera_position[3];
		float camera_front[3];
		float camera_top[3];
		wchar_t identity[256];
		uint32_t context_len;
		unsigned char context[256];
		wchar_t description[2048];
	};

	void writeString(wchar_t *dest, size_t dest_size, const std::string &src);
	void zeroMem();

	bool m_connected = false;

#ifdef _WIN32
	void *m_handle = nullptr;
#endif
	int m_fd = -1;
	LinkedMem *m_mem = nullptr;
};
