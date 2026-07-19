// Luanti
// SPDX-License-Identifier: LGPL-2.1-or-later

#include "mumble_link.h"
#include "log.h"
#include "porting.h"

#ifdef _WIN32
#include <windows.h>
#include <stringapiset.h>
#else
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <cstring>
#endif

MumbleLink::MumbleLink()
{
	init();
}

MumbleLink::~MumbleLink()
{
	if (m_mem) {
		zeroMem();
	}

#ifdef _WIN32
	if (m_mem)
		UnmapViewOfFile(m_mem);
	if (m_handle)
		CloseHandle(m_handle);
#else
	if (m_mem != nullptr && m_mem != MAP_FAILED)
		munmap(m_mem, sizeof(LinkedMem));
	if (m_fd >= 0)
		close(m_fd);
#endif
}

void MumbleLink::init()
{
#ifdef _WIN32
	m_handle = OpenFileMappingW(FILE_MAP_ALL_ACCESS, FALSE, L"MumbleLink");
	if (!m_handle) {
		m_connected = false;
		infostream << "MumbleLink: Mumble not running (OpenFileMapping failed)" << std::endl;
		return;
	}

	m_mem = (LinkedMem *)MapViewOfFile(m_handle, FILE_MAP_ALL_ACCESS, 0, 0,
					   sizeof(LinkedMem));
	if (!m_mem) {
		CloseHandle(m_handle);
		m_handle = nullptr;
		m_connected = false;
		infostream << "MumbleLink: MapViewOfFile failed" << std::endl;
		return;
	}
#else
	char path[64];
	snprintf(path, sizeof(path), "/MumbleLink.%d", getuid());

	m_fd = shm_open(path, O_RDWR, S_IRUSR | S_IWUSR);
	if (m_fd < 0) {
		m_connected = false;
		infostream << "MumbleLink: Mumble not running (shm_open failed)" << std::endl;
		return;
	}

	m_mem = (LinkedMem *)mmap(nullptr, sizeof(LinkedMem),
				  PROT_READ | PROT_WRITE, MAP_SHARED, m_fd, 0);
	if (m_mem == MAP_FAILED) {
		close(m_fd);
		m_fd = -1;
		m_mem = nullptr;
		m_connected = false;
		infostream << "MumbleLink: mmap failed" << std::endl;
		return;
	}
#endif

	infostream << "MumbleLink: Connected successfully" << std::endl;
	m_connected = true;

	m_mem->ui_version = 2;
	m_mem->ui_tick = 0;

	writeString(m_mem->name, 256, "Luanti");
	writeString(m_mem->description, 2048, "Luanti positional audio");
}

void MumbleLink::setContext(const std::string &context)
{
	if (!m_connected || !m_mem)
		return;

	size_t len = context.size();
	if (len > 256)
		len = 256;
	memcpy(m_mem->context, context.data(), len);
	m_mem->context_len = (uint32_t)len;
	infostream << "MumbleLink: Context set to \"" << context << "\"" << std::endl;
}

void MumbleLink::setIdentity(const std::string &identity)
{
	if (!m_connected || !m_mem)
		return;

	writeString(m_mem->identity, 256, identity);
}

void MumbleLink::update(v3f camera_pos, v3f camera_dir, v3f camera_up,
			v3f player_pos, v3f player_dir, v3f player_up)
{
	if (!m_connected || !m_mem)
		return;

	m_mem->ui_tick++;

	m_mem->avatar_position[0] = player_pos.X;
	m_mem->avatar_position[1] = player_pos.Y;
	m_mem->avatar_position[2] = player_pos.Z;
	m_mem->avatar_front[0] = player_dir.X;
	m_mem->avatar_front[1] = player_dir.Y;
	m_mem->avatar_front[2] = player_dir.Z;
	m_mem->avatar_top[0] = player_up.X;
	m_mem->avatar_top[1] = player_up.Y;
	m_mem->avatar_top[2] = player_up.Z;

	m_mem->camera_position[0] = camera_pos.X;
	m_mem->camera_position[1] = camera_pos.Y;
	m_mem->camera_position[2] = camera_pos.Z;
	m_mem->camera_front[0] = camera_dir.X;
	m_mem->camera_front[1] = camera_dir.Y;
	m_mem->camera_front[2] = camera_dir.Z;
	m_mem->camera_top[0] = camera_up.X;
	m_mem->camera_top[1] = camera_up.Y;
	m_mem->camera_top[2] = camera_up.Z;
}

void MumbleLink::writeString(wchar_t *dest, size_t dest_size, const std::string &src)
{
	if (dest_size == 0)
		return;

	size_t i = 0;
#ifdef _WIN32
	int len = MultiByteToWideChar(CP_UTF8, 0, src.c_str(), -1,
				      dest, (int)dest_size - 1);
	if (len > 0)
		dest[len] = L'\0';
	else
		dest[0] = L'\0';
#else
	for (char c : src) {
		if (i >= dest_size - 1)
			break;
		dest[i++] = (wchar_t)(unsigned char)c;
	}
	dest[i] = L'\0';
#endif
}

void MumbleLink::zeroMem()
{
	if (!m_mem)
		return;

	LinkedMem zero = {};
	memcpy(m_mem, &zero, sizeof(LinkedMem));
}
