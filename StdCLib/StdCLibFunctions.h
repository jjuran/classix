//
// StdCLibFunctions.h
// Classix
//
// Copyright (C) 2012 Félix Cloutier
//
// This file is part of Classix.
//
// Classix is free software: you can redistribute it and/or modify it under the
// terms of the GNU General Public License as published by the Free Software
// Foundation, either version 3 of the License, or (at your option) any later
// version.
//
// Classix is distributed in the hope that it will be useful, but WITHOUT ANY
// WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
// A PARTICULAR PURPOSE. See the GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License along with
// Classix. If not, see http://www.gnu.org/licenses/.
//

#ifndef Classix_StdCLibFunctions_h
#define Classix_StdCLibFunctions_h

namespace PPCVM
{
	struct MachineState;
}

namespace StdCLib
{
	struct Globals;
}

extern "C"
{
	// <init> function
	void StdCLib___StdCLib_IntEnvInit(StdCLib::Globals* globals, PPCVM::MachineState* state);

	// actual StdCLib interface
	void StdCLib___abort(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib___assertprint(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib___DebugMallocHeap(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib___GetTrapType(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib___growFileTable(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib___NumToolboxTraps(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib___RestoreInitialCFragWorld(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib___RevertCFragWorld(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib___setjmp(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib___vec_longjmp(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib___vec_setjmp(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__addDevHandler(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__badPtr(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__Bogus(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__BreakPoint(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__bufsync(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__c2pstrcpy(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__coClose(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__coExit(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__coFAccess(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__coIoctl(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__coRead(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__coreIOExit(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__coWrite(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__cvt(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__DoExitProcs(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__doprnt(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__doscan(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__exit(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__faccess(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__filbuf(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__findiop(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__flsbuf(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__fsClose(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__fsFAccess(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__fsIoctl(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__fsRead(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__FSSpec2Path(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__fsWrite(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__GetAliasInfo(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__getDevHandler(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__getIOPort(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__memchr(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__memcpy(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__ResolveFileAlias(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__rmemcpy(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__RTExit(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__RTInit(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__SA_DeletePtr(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__SA_GetPID(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__SA_SetPtrSize(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__syClose(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__syFAccess(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__syIoctl(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__syRead(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__syWrite(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__uerror(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__wrtchk(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib__xflsbuf(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_abort(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_abs(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_access(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_asctime(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_atexit(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_atof(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_atoi(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_atol(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_atoll(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_binhex(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_bsearch(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_calloc(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_clearerr(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_clock(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_close(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_ConvertTheString(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_creat(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_ctime(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_difftime(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_div(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_dup(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_ecvt(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_exit(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_faccess(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_fclose(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_fcntl(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_fcvt(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_fdopen(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_feof(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_ferror(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_fflush(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_fgetc(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_fgetpos(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_fgets(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_fopen(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_fprintf(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_fputc(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_fputs(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_fread(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_free(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_freopen(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_fscanf(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_fseek(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_fsetfileinfo(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_fsetpos(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_FSMakeFSSpec_Long(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_FSp_creat(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_FSp_faccess(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_FSp_fopen(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_FSp_freopen(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_FSp_fsetfileinfo(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_FSp_open(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_FSp_remove(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_FSp_rename(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_FSp_unlink(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_FSSpec2Path_Long(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_ftell(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_fwrite(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_getc(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_getchar(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_getenv(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_getIDstring(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_getpid(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_gets(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_getw(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_gmtime(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_IEResolvePath(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_ioctl(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_isalnum(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_isalpha(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_isascii(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_iscntrl(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_isdigit(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_isgraph(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_islower(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_isprint(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_ispunct(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_isspace(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_isupper(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_isxdigit(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_labs(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_ldiv(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_llabs(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_lldiv(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_localeconv(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_localtime(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_longjmp(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_lseek(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_MakeResolvedFSSpec(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_MakeResolvedFSSpec_Long(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_MakeResolvedPath(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_MakeResolvedPath_Long(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_MakeTheLocaleString(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_malloc(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_mblen(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_mbstowcs(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_mbtowc(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_memccpy(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_memchr(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_memcmp(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_memcpy(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_memmove(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_memset(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_mktemp(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_mktime(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_open(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_ParseTheLocaleString(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_perror(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_PLpos(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_PLstrcat(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_PLstrchr(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_PLstrcmp(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_PLstrcpy(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_PLstrlen(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_PLstrncat(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_PLstrncmp(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_PLstrncpy(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_PLstrpbrk(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_PLstrrchr(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_PLstrspn(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_PLstrstr(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_printf(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_putc(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_putchar(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_puts(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_putw(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_qsort(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_raise(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_rand(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_read(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_realloc(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_remove(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_rename(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_ResolveFolderAliases(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_ResolveFolderAliases_Long(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_ResolvePath(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_ResolvePath_Long(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_rewind(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_scanf(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_setbuf(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_setenv(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_setlocale(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_setvbuf(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_signal(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_sprintf(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_srand(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_sscanf(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_strcat(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_strchr(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_strcmp(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_strcoll(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_strcpy(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_strcspn(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_strerror(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_strftime(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_strlen(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_strncat(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_strncmp(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_strncpy(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_strpbrk(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_strrchr(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_strspn(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_strstr(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_strtod(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_strtok(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_strtol(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_strtoll(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_strtoul(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_strtoull(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_strxfrm(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_system(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_time(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_tmpfile(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_tmpnam(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_toascii(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_tolower(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_toupper(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_TrapAvailable(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_ungetc(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_unlink(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_vec_calloc(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_vec_free(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_vec_malloc(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_vec_realloc(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_vfprintf(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_vprintf(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_vsprintf(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_wcstombs(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_wctomb(StdCLib::Globals* globals, PPCVM::MachineState* state);
	void StdCLib_write(StdCLib::Globals* globals, PPCVM::MachineState* state);
}

#endif
