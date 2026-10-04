/*
 * hostid_probe.c — differential probe for the machine-identity inputs FlexNet (tabfnp.dll,
 * FNP_Act_Installer.dll, custactutil*.exe/dll, atrdiag.exe) reads when it computes a hostid.
 *
 * Build (mingw-w64, 64-bit):
 *   x86_64-w64-mingw32-gcc -O1 -Wall -o bin/hostid_probe.exe hostid_probe.c \
 *       -lsetupapi -liphlpapi -lnetapi32 -lole32 -loleaut32 -luuid -lwbemuuid
 *
 * Output is one `key=value` per line, grouped by `[section]` markers, values are `"..."` for
 * strings (non-printables replaced by '.'), hex for handles/serials/HRESULTs and decimal for
 * sizes/counts.  Every API call is preceded by SetLastError(0) and prints
 * `ok=` / `lastError=` immediately, so a diff between the Windows and Wine runs is line-by-line.
 *
 * Everything is best-effort: a failure prints the HRESULT/lastError and the probe continues, so
 * that "absent" is distinguishable from "present but wrong".
 */
#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0601
#define UNICODE
#define _UNICODE

#include <winapifamily.h>
#ifdef WINAPI_FAMILY
#undef WINAPI_FAMILY
#endif
#define WINAPI_FAMILY WINAPI_FAMILY_DESKTOP_APP

#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <winternl.h>
#include <winioctl.h>
#include <setupapi.h>
#include <iphlpapi.h>
#include <lm.h>
#include <wbemidl.h>
#include <oleauto.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdarg.h>
#include <string.h>

/* GUID_DEVCLASS_NET = {4d36e972-e325-11ce-bfc1-08002be10318} (devguid.h, hardcoded to avoid
 * the DEFINE_GUID/EXTERN_C ambiguity in the mingw headers). */
static const GUID guid_devclass_net =
    { 0x4d36e972, 0xe325, 0x11ce, { 0xbf, 0xc1, 0x08, 0x00, 0x2b, 0xe1, 0x03, 0x18 } };

/* The mingw/Windows SDK does not define SPDRP_NETWORKADDRESS; the value below is the property the
 * Flexera hostid helpers are usually described as reading.  NOTE: 0x16 is documented in the SDK as
 * SPDRP_ENUMERATOR_NAME, and this Tableau build's tabfnp.dll actually calls
 * SetupDiGetDeviceRegistryPropertyA with property 0 (SPDRP_DEVICEDESC) - see recon/HOSTID_PROBES.md.
 * Both are probed below so neither interpretation is lost. */
#ifndef SPDRP_NETWORKADDRESS
#define SPDRP_NETWORKADDRESS 0x00000016
#endif

/* 'RSMB' in the Win32 sense: 'R' is the most significant byte (0x52534D42), matching Wine's own
 * ntdll/unix/system.c `#define RSMB 0x52534D42` and the kernel32 test. */
#define RAW_SMBIOS ('R' << 24 | 'S' << 16 | 'M' << 8 | 'B')

static void p( const char *fmt, ... )
{
    va_list ap;
    va_start( ap, fmt );
    vprintf( fmt, ap );
    va_end( ap );
    fflush( stdout );
}

/* ---- string emission ---------------------------------------------------------------- */

static void emit_raw( const char *key, const char *s, size_t len )
{
    size_t i;
    printf( "%s=\"", key );
    for (i = 0; i < len; i++)
    {
        unsigned char c = (unsigned char)s[i];
        putchar( (c >= 0x20 && c < 0x7f) ? c : '.' );
    }
    printf( "\"\n" );
    fflush( stdout );
}

static void emit_str( const char *key, const char *s )
{
    if (!s) { printf( "%s=<null>\n", key ); fflush( stdout ); return; }
    emit_raw( key, s, strlen( s ) );
}

static void emit_wstr( const char *key, const WCHAR *w )
{
    char buf[1024];
    int n;

    if (!w) { printf( "%s=<null>\n", key ); fflush( stdout ); return; }
    n = WideCharToMultiByte( CP_UTF8, 0, w, -1, buf, sizeof(buf) - 1, NULL, NULL );
    if (n <= 0) { printf( "%s=<conv-error lastError=%lu>\n", key, (unsigned long)GetLastError() ); fflush( stdout ); return; }
    buf[n - 1] = 0;
    emit_str( key, buf );
}

/* ---- 1. computer / user / domain ---------------------------------------------------- */

static void probe_computer( void )
{
    WCHAR name[256];
    DWORD size = ARRAYSIZE( name );
    LPWKSTA_INFO_100 wksta = NULL;
    NET_API_STATUS st;

    p( "[computer]\n" );

    SetLastError( 0 );
    if (GetComputerNameW( name, &size ))
        emit_wstr( "computer.GetComputerNameW.name", name );
    else
        p( "computer.GetComputerNameW.name=<fail>\n" );
    p( "computer.GetComputerNameW.ok=%d lastError=%lu\n", size != 0, (unsigned long)GetLastError() );

    size = ARRAYSIZE( name );
    SetLastError( 0 );
    if (GetUserNameW( name, &size ))
        emit_wstr( "computer.GetUserNameW.name", name );
    else
        p( "computer.GetUserNameW.name=<fail>\n" );
    p( "computer.GetUserNameW.ok=%d lastError=%lu\n", size != 0, (unsigned long)GetLastError() );

    SetLastError( 0 );
    st = NetWkstaGetInfo( NULL, 100, (LPBYTE *)&wksta );
    p( "computer.NetWkstaGetInfo.status=%lu lastError=%lu\n", (unsigned long)st, (unsigned long)GetLastError() );
    if (st == NERR_Success && wksta)
    {
        emit_wstr( "computer.NetWkstaGetInfo.computername", wksta->wki100_computername );
        emit_wstr( "computer.NetWkstaGetInfo.langroup", wksta->wki100_langroup );
        p( "computer.NetWkstaGetInfo.ver_major=%lu ver_minor=%lu platform_id=%lu\n",
           (unsigned long)wksta->wki100_ver_major, (unsigned long)wksta->wki100_ver_minor,
           (unsigned long)wksta->wki100_platform_id );
        NetApiBufferFree( wksta );
    }

    {
        WCHAR buf[256];
        DWORD len = ARRAYSIZE( buf );
        if (GetComputerNameExW( ComputerNameDnsHostname, buf, &len )) emit_wstr( "computer.dnshostname", buf );
        else p( "computer.dnshostname=<fail lastError=%lu>\n", (unsigned long)GetLastError() );
    }
}

/* ---- 2. volume identity ------------------------------------------------------------- */

static void probe_volume( void )
{
    WCHAR label[256] = {0}, fsname[256] = {0};
    DWORD serial = 0, maxlen = 0, flags = 0;
    BOOL ok;

    p( "[volume]\n" );

    SetLastError( 0 );
    ok = GetVolumeInformationW( L"C:\\", label, ARRAYSIZE( label ), &serial, &maxlen, &flags,
                                fsname, ARRAYSIZE( fsname ) );
    p( "volume.GetVolumeInformationW.C.ok=%d lastError=%lu serial=0x%08lx serial_dec=%lu label=\"%ls\" "
       "fsname=\"%ls\" maxcomponentlen=%lu flags=0x%08lx\n",
       ok, (unsigned long)GetLastError(), (unsigned long)serial, (unsigned long)serial,
       label, fsname, (unsigned long)maxlen, (unsigned long)flags );

    /* raw volume handle: extents + the volume's own serial via ioctl */
    {
        HANDLE h;
        DWORD ret = 0;
        BYTE buf[sizeof(VOLUME_DISK_EXTENTS) + 4 * sizeof(DISK_EXTENT)];

        SetLastError( 0 );
        h = CreateFileW( L"\\\\.\\C:", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
                         OPEN_EXISTING, 0, NULL );
        p( "volume.open.C.ok=%d lastError=%lu handle=%p\n", h != INVALID_HANDLE_VALUE,
           (unsigned long)GetLastError(), h );
        if (h != INVALID_HANDLE_VALUE)
        {
            memset( buf, 0, sizeof(buf) );
            SetLastError( 0 );
            ok = DeviceIoControl( h, IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS, NULL, 0,
                                  buf, sizeof(buf), &ret, NULL );
            p( "volume.IOCTL_VOLUME_GET_VOLUME_DISK_EXTENTS.ok=%d lastError=%lu bytesReturned=%lu\n",
               ok, (unsigned long)GetLastError(), (unsigned long)ret );
            if (ok)
            {
                VOLUME_DISK_EXTENTS *e = (VOLUME_DISK_EXTENTS *)buf;
                DWORD i;
                p( "volume.extents.number=%lu\n", (unsigned long)e->NumberOfDiskExtents );
                for (i = 0; i < e->NumberOfDiskExtents && i < 4; i++)
                    p( "volume.extent.%lu.disks=%lu start=0x%llx length=0x%llx\n", (unsigned long)i,
                       (unsigned long)e->Extents[i].DiskNumber,
                       (unsigned long long)e->Extents[i].StartingOffset.QuadPart,
                       (unsigned long long)e->Extents[i].ExtentLength.QuadPart );
            }
            CloseHandle( h );
        }
    }
}

/* ---- 3. physical drive / storage descriptor ----------------------------------------- */

static void probe_physical_drive( void )
{
    HANDLE h;
    STORAGE_PROPERTY_QUERY query;
    BYTE out[1024];
    DWORD ret = 0;
    BOOL ok;

    p( "[physicaldrive]\n" );

    SetLastError( 0 );
    h = CreateFileW( L"\\\\.\\PhysicalDrive0", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE,
                     NULL, OPEN_EXISTING, 0, NULL );
    p( "pd0.open.ok=%d lastError=%lu handle=%p\n", h != INVALID_HANDLE_VALUE,
       (unsigned long)GetLastError(), h );
    if (h == INVALID_HANDLE_VALUE) return;

    memset( &query, 0, sizeof(query) );
    query.PropertyId = StorageDeviceProperty;
    query.QueryType  = PropertyStandardQuery;
    memset( out, 0, sizeof(out) );

    SetLastError( 0 );
    ok = DeviceIoControl( h, IOCTL_STORAGE_QUERY_PROPERTY, &query, sizeof(query), out, sizeof(out), &ret, NULL );
    p( "pd0.IOCTL_STORAGE_QUERY_PROPERTY.ok=%d lastError=%lu bytesReturned=%lu\n",
       ok, (unsigned long)GetLastError(), (unsigned long)ret );
    if (ok && ret >= sizeof(STORAGE_DEVICE_DESCRIPTOR))
    {
        STORAGE_DEVICE_DESCRIPTOR *d = (STORAGE_DEVICE_DESCRIPTOR *)out;
        p( "pd0.desc.version=%lu size=%lu devicetype=0x%lx modifier=0x%lx removable=%u queueing=%u "
           "bustype=%lu rawprops=%lu vendor_off=%lu product_off=%lu revision_off=%lu serial_off=%lu\n",
           (unsigned long)d->Version, (unsigned long)d->Size, (unsigned long)d->DeviceType,
           (unsigned long)d->DeviceTypeModifier, d->RemovableMedia, d->CommandQueueing,
           (unsigned long)d->BusType, (unsigned long)d->RawPropertiesLength,
           (unsigned long)d->VendorIdOffset, (unsigned long)d->ProductIdOffset,
           (unsigned long)d->ProductRevisionOffset, (unsigned long)d->SerialNumberOffset );
        emit_str( "pd0.vendor",   d->VendorIdOffset        ? (char *)out + d->VendorIdOffset        : "" );
        emit_str( "pd0.product",  d->ProductIdOffset       ? (char *)out + d->ProductIdOffset       : "" );
        emit_str( "pd0.revision", d->ProductRevisionOffset ? (char *)out + d->ProductRevisionOffset : "" );
        emit_str( "pd0.serial",   d->SerialNumberOffset    ? (char *)out + d->SerialNumberOffset    : "" );
    }

    /* header-only size query, to see whether a second call agrees (Wine returns the same) */
    memset( out, 0, sizeof(out) );
    ret = 0;
    SetLastError( 0 );
    ok = DeviceIoControl( h, IOCTL_STORAGE_QUERY_PROPERTY, &query, sizeof(query), out,
                          sizeof(STORAGE_DESCRIPTOR_HEADER), &ret, NULL );
    p( "pd0.sizequery.ok=%d lastError=%lu bytesReturned=%lu size=%lu\n", ok,
       (unsigned long)GetLastError(), (unsigned long)ret,
       ok && ret >= sizeof(STORAGE_DESCRIPTOR_HEADER) ? (unsigned long)((STORAGE_DESCRIPTOR_HEADER *)out)->Size : 0 );

    CloseHandle( h );
}

/* ---- 4. iphlpapi adapters ----------------------------------------------------------- */

static void probe_adapters( void )
{
    ULONG size = 0, i;
    IP_ADAPTER_INFO *info = NULL, *a;
    PIP_ADAPTER_ADDRESSES addrs = NULL;
    ULONG st;

    p( "[adapters]\n" );

    SetLastError( 0 );
    st = GetAdaptersInfo( NULL, &size );
    p( "adapters.GetAdaptersInfo.size.status=%lu needed=%lu lastError=%lu\n",
       (unsigned long)st, (unsigned long)size, (unsigned long)GetLastError() );
    if (size)
    {
        info = malloc( size );
        if (info)
        {
            SetLastError( 0 );
            st = GetAdaptersInfo( info, &size );
            p( "adapters.GetAdaptersInfo.status=%lu lastError=%lu\n", (unsigned long)st, (unsigned long)GetLastError() );
            if (st == ERROR_SUCCESS)
            {
                i = 0;
                for (a = info; a; a = a->Next)
                {
                    char key[64], mac[64];
                    unsigned int j;
                    mac[0] = 0;
                    for (j = 0; j < a->AddressLength && j < 8; j++)
                        sprintf( mac + strlen( mac ), "%s%02X", j ? ":" : "", a->Address[j] );
                    sprintf( key, "adapters.GetAdaptersInfo.%lu", (unsigned long)i );
                    p( "%s.type=%lu dhcp=%lu addrlen=%lu mac=\"%s\"\n", key, (unsigned long)a->Type,
                       (unsigned long)a->DhcpEnabled, (unsigned long)a->AddressLength, mac );
                    sprintf( key, "adapters.GetAdaptersInfo.%lu.desc", (unsigned long)i );
                    emit_str( key, a->Description );
                    sprintf( key, "adapters.GetAdaptersInfo.%lu.ip", (unsigned long)i );
                    emit_str( key, a->IpAddressList.IpAddress.String );
                    i++;
                }
                p( "adapters.GetAdaptersInfo.count=%lu\n", (unsigned long)i );
            }
            free( info );
        }
    }

    size = 0;
    SetLastError( 0 );
    st = GetAdaptersAddresses( AF_UNSPEC, GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST |
                               GAA_FLAG_SKIP_DNS_SERVER, NULL, NULL, &size );
    p( "adapters.GetAdaptersAddresses.size.status=%lu needed=%lu lastError=%lu\n",
       (unsigned long)st, (unsigned long)size, (unsigned long)GetLastError() );
    if (size)
    {
        addrs = malloc( size );
        if (addrs)
        {
            SetLastError( 0 );
            st = GetAdaptersAddresses( AF_UNSPEC, GAA_FLAG_SKIP_ANYCAST | GAA_FLAG_SKIP_MULTICAST |
                                       GAA_FLAG_SKIP_DNS_SERVER, NULL, addrs, &size );
            p( "adapters.GetAdaptersAddresses.status=%lu lastError=%lu\n", (unsigned long)st,
               (unsigned long)GetLastError() );
            if (st == ERROR_SUCCESS)
            {
                PIP_ADAPTER_ADDRESSES aa;
                i = 0;
                for (aa = addrs; aa; aa = aa->Next)
                {
                    char key[64], mac[64];
                    unsigned int j;
                    mac[0] = 0;
                    for (j = 0; j < aa->PhysicalAddressLength && j < 8; j++)
                        sprintf( mac + strlen( mac ), "%s%02X", j ? ":" : "", aa->PhysicalAddress[j] );
                    sprintf( key, "adapters.GetAdaptersAddresses.%lu", (unsigned long)i );
                    p( "%s.iftype=%lu operstatus=%lu addrlen=%lu mac=\"%s\"\n", key,
                       (unsigned long)aa->IfType, (unsigned long)aa->OperStatus,
                       (unsigned long)aa->PhysicalAddressLength, mac );
                    sprintf( key, "adapters.GetAdaptersAddresses.%lu.friendlyname", (unsigned long)i );
                    emit_wstr( key, aa->FriendlyName );
                    sprintf( key, "adapters.GetAdaptersAddresses.%lu.desc", (unsigned long)i );
                    emit_wstr( key, aa->Description );
                    i++;
                }
                p( "adapters.GetAdaptersAddresses.count=%lu\n", (unsigned long)i );
            }
            free( addrs );
        }
    }
}

/* ---- 5. SetupAPI PnP net devices ---------------------------------------------------- */

static void probe_setupapi( void )
{
    HDEVINFO set;
    SP_DEVINFO_DATA data;
    DWORD i = 0;
    const DWORD flags[] = { DIGCF_PRESENT, 0 };

    p( "[pnpnet]\n" );

    for (i = 0; i < ARRAYSIZE( flags ); i++)
    {
        char prefix[80];
        DWORD n = 0, idx = 0;

        sprintf( prefix, "pnpnet.GUID_DEVCLASS_NET.flags%s", flags[i] ? "_PRESENT" : "_ALL" );
        SetLastError( 0 );
        set = SetupDiGetClassDevsW( &guid_devclass_net, NULL, NULL, flags[i] );
        p( "%s.ok=%d lastError=%lu handle=%p\n", prefix, set != INVALID_HANDLE_VALUE,
           (unsigned long)GetLastError(), set );
        if (set == INVALID_HANDLE_VALUE) continue;

        memset( &data, 0, sizeof(data) );
        data.cbSize = sizeof(data);
        while (SetupDiEnumDeviceInfo( set, n, &data ))
        {
            static const DWORD props[] = { SPDRP_DEVICEDESC, SPDRP_FRIENDLYNAME, SPDRP_NETWORKADDRESS,
                                           SPDRP_HARDWAREID, SPDRP_DRIVER };
            static const char *names[] = { "devicedesc", "friendlyname", "prop16_networkaddress",
                                           "hardwareid", "driver" };
            DWORD k;
            char key[96];

            for (k = 0; k < ARRAYSIZE( props ); k++)
            {
                BYTE buf[1024];
                DWORD type = 0, needed = 0;

                SetLastError( 0 );
                if (SetupDiGetDeviceRegistryPropertyW( set, &data, props[k], &type, buf, sizeof(buf), &needed ))
                {
                    sprintf( key, "%s.%lu.%s", prefix, (unsigned long)idx, names[k] );
                    emit_wstr( key, (WCHAR *)buf );
                }
                else
                {
                    p( "%s.%lu.%s=<err lastError=%lu>\n", prefix, (unsigned long)idx, names[k],
                       (unsigned long)GetLastError() );
                }
            }
            /* SetupDiGetDeviceInstanceIdW is also called by tabfnp.dll/custactutil_libFNP.dll */
            {
                WCHAR buf[1024];
                DWORD needed = 0;
                SetLastError( 0 );
                if (SetupDiGetDeviceInstanceIdW( set, &data, buf, ARRAYSIZE( buf ), &needed ))
                {
                    sprintf( key, "%s.%lu.instanceid", prefix, (unsigned long)idx );
                    emit_wstr( key, buf );
                }
                else
                    p( "%s.%lu.instanceid=<err lastError=%lu>\n", prefix, (unsigned long)idx,
                       (unsigned long)GetLastError() );
            }
            idx++;
            memset( &data, 0, sizeof(data) );
            data.cbSize = sizeof(data);
        }
        p( "%s.enum.count=%lu lastError=%lu\n", prefix, (unsigned long)idx, (unsigned long)GetLastError() );
        SetupDiDestroyDeviceInfoList( set );
    }
}

/* ---- 6. SMBIOS via GetSystemFirmwareTable('RSMB') ----------------------------------- */

static const char *smbios_string( const BYTE *fmt, DWORD fmt_len, BYTE index )
{
    const BYTE *s = fmt + fmt_len;
    BYTE n = 1;
    if (!index) return "";
    while (n < index)
    {
        if (s[0] == 0) return "";
        while (s[0]) s++;
        s++;
        n++;
    }
    return (const char *)s;
}

static void probe_smbios( void )
{
    UINT len, got;
    BYTE *buf;
    DWORD off;

    p( "[smbios]\n" );

    SetLastError( 0 );
    len = GetSystemFirmwareTable( RAW_SMBIOS, 0, NULL, 0 );
    p( "smbios.GetSystemFirmwareTable.size=%u lastError=%lu\n", len, (unsigned long)GetLastError() );
    if (!len) return;

    buf = malloc( len );
    if (!buf) { p( "smbios.alloc=<failed>\n" ); return; }
    memset( buf, 0, len );
    SetLastError( 0 );
    got = GetSystemFirmwareTable( RAW_SMBIOS, 0, buf, len );
    p( "smbios.GetSystemFirmwareTable.ok=%u size=%u lastError=%lu\n", got, len,
       (unsigned long)GetLastError() );
    if (got < 8 || got > len) { free( buf ); return; }

    /* RawSMBIOSData: Used20CallingMethod(1) MajorVersion(1) MinorVersion(1) DmiRevision(1) Length(4) */
    p( "smbios.header.used20=%u major=%u minor=%u dmi_revision=%u length=%lu\n",
       buf[0], buf[1], buf[2], buf[3],
       (unsigned long)*(DWORD *)(buf + 4) );

    off = 8;
    {
        DWORD n = 0;
        DWORD table_len = *(DWORD *)(buf + 4);

        while (off + 4 <= 8 + table_len && buf[off] != 127)
        {
            BYTE type = buf[off];
            BYTE hlen = buf[off + 1];
            WORD handle = *(WORD *)(buf + off + 2);
            const BYTE *fmt = buf + off;
            DWORD str_off;

            if (hlen < 4 || off + hlen > 8 + table_len) break;
            str_off = off + hlen;
            /* skip the string area: strings until a double NUL */
            {
                DWORD s = str_off;
                if (s < 8 + table_len)
                {
                    if (buf[s] == 0) s++;
                    else
                    {
                        while (s + 1 < 8 + table_len && !(buf[s] == 0 && buf[s + 1] == 0)) s++;
                        s += 2;
                    }
                }
                p( "smbios.struct.%lu.type=%u handle=0x%04x length=%u\n", (unsigned long)n,
                   type, handle, hlen );
                if (type == 0)   /* BIOS */
                    p( "smbios.struct.%lu.vendor=\"%s\" version=\"%s\" date=\"%s\"\n", (unsigned long)n,
                       smbios_string( fmt, hlen, fmt[4] ), smbios_string( fmt, hlen, fmt[5] ),
                       smbios_string( fmt, hlen, fmt[6] ) );
                if (type == 1)   /* System Information: uuid at 0x08 */
                {
                    const BYTE *u = fmt + 8;
                    p( "smbios.struct.%lu.system.manufacturer=\"%s\" product=\"%s\" version=\"%s\" "
                       "serial=\"%s\" sku=\"%s\" family=\"%s\"\n", (unsigned long)n,
                       smbios_string( fmt, hlen, fmt[4] ), smbios_string( fmt, hlen, fmt[5] ),
                       smbios_string( fmt, hlen, fmt[6] ), smbios_string( fmt, hlen, fmt[7] ),
                       hlen > 0x19 ? smbios_string( fmt, hlen, fmt[0x19] ) : "",
                       hlen > 0x1a ? smbios_string( fmt, hlen, fmt[0x1a] ) : "" );
                    p( "smbios.struct.%lu.system.uuid_raw=%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X%02X "
                       "uuid_canonical=%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X\n",
                       (unsigned long)n,
                       u[0],u[1],u[2],u[3],u[4],u[5],u[6],u[7],u[8],u[9],u[10],u[11],u[12],u[13],u[14],u[15],
                       u[3],u[2],u[1],u[0],u[5],u[4],u[7],u[6],u[8],u[9],u[10],u[11],u[12],u[13],u[14],u[15] );
                }
                if (type == 2)   /* Baseboard */
                    p( "smbios.struct.%lu.baseboard.manufacturer=\"%s\" product=\"%s\" version=\"%s\" "
                       "serial=\"%s\" asset=\"%s\"\n", (unsigned long)n,
                       smbios_string( fmt, hlen, fmt[4] ), smbios_string( fmt, hlen, fmt[5] ),
                       smbios_string( fmt, hlen, fmt[6] ), smbios_string( fmt, hlen, fmt[7] ),
                       smbios_string( fmt, hlen, fmt[8] ) );
                if (type == 3)   /* Chassis */
                    p( "smbios.struct.%lu.chassis.manufacturer=\"%s\" version=\"%s\" serial=\"%s\"\n",
                       (unsigned long)n, smbios_string( fmt, hlen, fmt[4] ),
                       smbios_string( fmt, hlen, fmt[5] ), smbios_string( fmt, hlen, fmt[7] ) );
            }
            off = str_off;
            if (off < 8 + table_len && buf[off] == 0) off++;
            else { while (off + 1 < 8 + table_len && !(buf[off] == 0 && buf[off + 1] == 0)) off++; off += 2; }
            n++;
            if (n > 64) break;
        }
        p( "smbios.struct.count=%lu\n", (unsigned long)n );
    }
    free( buf );
}

/* ---- 7. WMI over COM ---------------------------------------------------------------- */

static IWbemServices *g_svc;

static void emit_variant( const char *key, VARIANT *v )
{
    switch (V_VT( v ))
    {
    case VT_BSTR:  emit_wstr( key, V_BSTR( v ) ); break;
    case VT_NULL:  printf( "%s=<null>\n", key ); fflush( stdout ); break;
    case VT_I4:    printf( "%s=%ld\n", key, (long)V_I4( v ) ); fflush( stdout ); break;
    case VT_UI4:   printf( "%s=%lu\n", key, (unsigned long)V_UI4( v ) ); fflush( stdout ); break;
    case VT_UI1:   printf( "%s=%u\n", key, (unsigned)V_UI1( v ) ); fflush( stdout ); break;
    case VT_BOOL:  printf( "%s=%d\n", key, V_BOOL( v ) ? 1 : 0 ); fflush( stdout ); break;
    case VT_EMPTY: printf( "%s=<empty>\n", key ); fflush( stdout ); break;
    default:       printf( "%s=<vt=%u>\n", key, (unsigned)V_VT( v ) ); fflush( stdout ); break;
    }
}

static void wmi_query( const char *class, const char *const *props )
{
    char wql[512], key[160];
    IEnumWbemClassObject *en = NULL;
    BSTR lang = SysAllocString( L"WQL" ), query;
    HRESULT hr;
    DWORD i = 0;
    size_t n;

    strcpy( wql, "SELECT " );
    for (n = 0; props[n]; n++)
    {
        if (n) strcat( wql, "," );
        strcat( wql, props[n] );
    }
    strcat( wql, " FROM " );
    strcat( wql, class );
    query = SysAllocString( L"" );
    {
        WCHAR wq[512];
        MultiByteToWideChar( CP_ACP, 0, wql, -1, wq, ARRAYSIZE( wq ) );
        SysFreeString( query );
        query = SysAllocString( wq );
    }

    SetLastError( 0 );
    hr = g_svc->lpVtbl->ExecQuery( g_svc, lang, query, WBEM_FLAG_FORWARD_ONLY | WBEM_FLAG_RETURN_IMMEDIATELY,
                                   NULL, &en );
    p( "wmi.%s.query.hr=0x%08lx\n", class, (unsigned long)hr );
    if (FAILED( hr ) || !en) { SysFreeString( lang ); SysFreeString( query ); return; }

    for (;;)
    {
        IWbemClassObject *obj = NULL;
        ULONG ret = 0;

        hr = en->lpVtbl->Next( en, WBEM_INFINITE, 1, &obj, &ret );
        if (hr != S_OK || !ret || !obj) break;

        for (n = 0; props[n]; n++)
        {
            WCHAR wp[64];
            VARIANT v;
            HRESULT ghr;

            MultiByteToWideChar( CP_ACP, 0, props[n], -1, wp, ARRAYSIZE( wp ) );
            VariantInit( &v );
            ghr = obj->lpVtbl->Get( obj, wp, 0, &v, NULL, NULL );
            sprintf( key, "wmi.%s.%lu.%s", class, (unsigned long)i, props[n] );
            if (SUCCEEDED( ghr )) emit_variant( key, &v );
            else { printf( "%s=<hr=0x%08lx>\n", key, (unsigned long)ghr ); fflush( stdout ); }
            VariantClear( &v );
        }
        obj->lpVtbl->Release( obj );
        i++;
        if (i > 64) break;
    }
    p( "wmi.%s.count=%lu\n", class, (unsigned long)i );
    en->lpVtbl->Release( en );
    SysFreeString( lang );
    SysFreeString( query );
}

static void probe_wmi( void )
{
    static const char *csp[]  = { "UUID", "Name", "Vendor", "Version", "IdentifyingNumber", NULL };
    static const char *bb[]   = { "Manufacturer", "Product", "SerialNumber", "Version", "Tag", NULL };
    static const char *pm[]   = { "SerialNumber", "Tag", NULL };
    static const char *na[]   = { "MACAddress", "Description", "Name", "DeviceID", "GUID", NULL };
    static const char *nac[]  = { "MACAddress", "Description", "SettingID", NULL };
    static const char *cs[]   = { "Name", "Domain", "UserName", "Manufacturer", "Model", NULL };
    IWbemLocator *loc = NULL;
    HRESULT hr;

    p( "[wmi]\n" );

    SetLastError( 0 );
    hr = CoInitializeEx( NULL, COINIT_MULTITHREADED );
    p( "wmi.CoInitializeEx.hr=0x%08lx lastError=%lu\n", (unsigned long)hr, (unsigned long)GetLastError() );

    hr = CoInitializeSecurity( NULL, -1, NULL, NULL, RPC_C_AUTHN_LEVEL_DEFAULT,
                               RPC_C_IMP_LEVEL_IMPERSONATE, NULL, EOAC_NONE, NULL );
    p( "wmi.CoInitializeSecurity.hr=0x%08lx\n", (unsigned long)hr );

    hr = CoCreateInstance( &CLSID_WbemLocator, NULL, CLSCTX_INPROC_SERVER, &IID_IWbemLocator, (void **)&loc );
    p( "wmi.CoCreateInstance.WbemLocator.hr=0x%08lx\n", (unsigned long)hr );
    if (FAILED( hr ) || !loc) return;

    {
        BSTR ns = SysAllocString( L"ROOT\\CIMV2" );
        hr = loc->lpVtbl->ConnectServer( loc, ns, NULL, NULL, NULL, 0, NULL, NULL, &g_svc );
        p( "wmi.ConnectServer.ROOT_CIMV2.hr=0x%08lx\n", (unsigned long)hr );
        SysFreeString( ns );
    }
    if (FAILED( hr ) || !g_svc) { loc->lpVtbl->Release( loc ); return; }

    hr = CoSetProxyBlanket( (IUnknown *)g_svc, RPC_C_AUTHN_WINNT, RPC_C_AUTHZ_NONE, NULL,
                            RPC_C_AUTHN_LEVEL_CALL, RPC_C_IMP_LEVEL_IMPERSONATE, NULL, EOAC_NONE );
    p( "wmi.CoSetProxyBlanket.hr=0x%08lx\n", (unsigned long)hr );

    wmi_query( "Win32_ComputerSystemProduct", csp );
    wmi_query( "Win32_BaseBoard", bb );
    wmi_query( "Win32_PhysicalMedia", pm );
    wmi_query( "Win32_NetworkAdapter", na );
    wmi_query( "Win32_NetworkAdapterConfiguration", nac );
    wmi_query( "Win32_ComputerSystem", cs );

    g_svc->lpVtbl->Release( g_svc );
    loc->lpVtbl->Release( loc );
}

/* ---- main --------------------------------------------------------------------------- */

typedef LONG (WINAPI *pRtlGetVersion)( PRTL_OSVERSIONINFOW );

int main( void )
{
    HMODULE ntdll;
    pRtlGetVersion rtl_get_version;

    p( "# hostid_probe v1\n" );
    p( "[meta]\n" );
#ifdef _WIN64
    p( "meta.arch=x86_64\n" );
#else
    p( "meta.arch=i386\n" );
#endif
    ntdll = GetModuleHandleW( L"ntdll.dll" );
    rtl_get_version = ntdll ? (pRtlGetVersion)(void *)GetProcAddress( ntdll, "RtlGetVersion" ) : NULL;
    if (rtl_get_version)
    {
        RTL_OSVERSIONINFOW vi;
        memset( &vi, 0, sizeof(vi) );
        vi.dwOSVersionInfoSize = sizeof(vi);
        if (rtl_get_version( &vi ) == 0)
            p( "meta.osversion=%lu.%lu build %lu platform %lu csd=\"%ls\"\n",
               (unsigned long)vi.dwMajorVersion, (unsigned long)vi.dwMinorVersion,
               (unsigned long)vi.dwBuildNumber, (unsigned long)vi.dwPlatformId, vi.szCSDVersion );
        else
            p( "meta.osversion=<RtlGetVersion failed>\n" );
    }
    else p( "meta.osversion=<no RtlGetVersion>\n" );

    probe_computer();
    probe_volume();
    probe_physical_drive();
    probe_adapters();
    probe_setupapi();
    probe_smbios();
    probe_wmi();

    p( "# end\n" );
    return 0;
}
