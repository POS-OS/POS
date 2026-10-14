/* userspec.c -- Parse a user and group string.
   Copyright (C) 1989-2026 Free Software Foundation, Inc.

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 3, or (at your option)
   any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public
   License along with this program.  If not, see
   <http://www.gnu.org/licenses/>. */

/* Written by David MacKenzie <djm@gnu.ai.mit.edu>.  */

#include <system.h>
#include <stdio.h>
#include <ctype.h>
#include <sys/types.h>
#include "cpiohdr.h"
#include "extern.h"

#ifndef HAVE_ENDPWENT
# define endpwent()
#endif
#ifndef HAVE_ENDGRENT
# define endgrent()
#endif

/* Return nonzero if STR represents an unsigned decimal integer,
   otherwise return 0. */

static int
isnumber_p (const char *str)
{
  for (; *str; str++)
    if (!isdigit (*str))
      return 0;
  return 1;
}

static void
store_string (char **bufptr, size_t *buflen, char *str)
{
  size_t len = strlen (str) + 1;
  if (len > *buflen)
    {
      *bufptr = xrealloc (*bufptr, len);
      *buflen = len;
    }
  strcpy (*bufptr, str);
}

/* Extract from NAME, which has the form "[user][:.][group]",
   a USERNAME, UID U, GROUPNAME, and GID G.
   Either user or group, or both, must be present.
   If the group is omitted but the ":" or "." separator is given,
   use the given user's login group.

   USERNAME and GROUPNAME will be in newly malloc'd memory.
   Either one might be NULL instead, indicating that it was not
   given and the corresponding numeric ID was left unchanged.

   Return NULL if successful, a static error message string if not.  */

const char *
parse_user_spec0 (char *spec, uid_t *uid, gid_t *gid,
		  char **username_arg, char **groupname_arg)
{
  static const char *tired = "virtual memory exhausted";
  const char *error_msg;
  struct passwd *pwd;
  struct group *grp;
  char *g, *u, *separator;
  char *groupname = NULL;
  size_t grouplen = 0;

  error_msg = NULL;
  *username_arg = *groupname_arg = NULL;
  groupname = NULL;

  /* Find the separator if there is one.  */
  separator = strchr (spec, ':');
  if (separator == NULL)
    separator = strchr (spec, '.');

  /* Replace separator with a NUL.  */
  if (separator != NULL)
    *separator = '\0';

  /* Set U and G to non-zero length strings corresponding to user and
     group specifiers or to NULL.  */
  u = (*spec == '\0' ? NULL : spec);

  g = (separator == NULL || *(separator + 1) == '\0'
       ? NULL
       : separator + 1);

  if (u == NULL && g == NULL)
    return "can not omit both user and group";

  if (u != NULL)
    {
      if (*u == '+')
	{
	  pwd = NULL;
	  ++u;
	}
      else
	pwd = getpwnam (u);

      if (pwd == NULL)
	{
	  if (!isnumber_p (u))
	    error_msg = _("invalid user");
	  else
	    {
	      int use_login_group;
	      use_login_group = (separator != NULL && g == NULL);
	      if (use_login_group)
		error_msg = _("cannot get the login group of a numeric UID");
	      else
		*uid = atoi (u);
	    }
	}
      else
	{
	  *uid = pwd->pw_uid;
	  if (g == NULL && separator != NULL)
	    {
	      /* A separator was given, but a group was not specified,
		 so get the login group.  */
	      *gid = pwd->pw_gid;
	      grp = getgrgid (pwd->pw_gid);
	      if (grp == NULL)
		{
		  char nbuf[UINTMAX_STRSIZE_BOUND];
		  store_string (&groupname, &grouplen,
				umaxtostr (pwd->pw_gid, nbuf));
		}
	      else
		{
		  store_string (&groupname, &grouplen, grp->gr_name);
		}
	      endgrent ();
	    }
	}
      endpwent ();
    }

  if (g != NULL && error_msg == NULL)
    {
      /* Explicit group.  */
      if (*g == '+')
	{
	  grp = NULL;
	  ++g;
	}
      else
	grp = getgrnam (g);

      if (grp == NULL)
	{
	  if (!isnumber_p (g))
	    error_msg = _("invalid group");
	  else
	    *gid = atoi (g);
	}
      else
	*gid = grp->gr_gid;
      endgrent ();		/* Save a file descriptor.  */

      if (error_msg == NULL)
	store_string (&groupname, &grouplen, g);
    }

  if (error_msg == NULL)
    {
      if (u != NULL)
	{
	  *username_arg = strdup (u);
	  if (*username_arg == NULL)
	    error_msg = tired;
	}

      if (groupname != NULL && error_msg == NULL)
	*groupname_arg = groupname;
    }
  else
    free (groupname);

  return error_msg;
}

const char *
parse_user_spec (const char *spec_arg, uid_t *uid, gid_t *gid,
		 char **username, char **groupname)
{
  char *spec = xstrdup (spec_arg);
  const char *retval = parse_user_spec0 (spec, uid, gid, username, groupname);
  free (spec);
  return retval;
}

#ifdef TEST

#define NULL_CHECK(s) ((s) == NULL ? "(null)" : (s))

int
main (int argc, char **argv)
{
  int i;

  for (i = 1; i < argc; i++)
    {
      const char *e;
      char *username, *groupname;
      uid_t uid;
      gid_t gid;
      char *tmp;

      tmp = strdup (argv[i]);
      e = parse_user_spec (tmp, &uid, &gid, &username, &groupname);
      free (tmp);
      printf ("%s: %u %u %s %s %s\n",
	      argv[i],
	      (unsigned int) uid,
	      (unsigned int) gid,
	      NULL_CHECK (username),
	      NULL_CHECK (groupname),
	      NULL_CHECK (e));
    }

  exit (0);
}

#endif
