#if !defined(ALIAS_NAME) || !defined(ALIAS_VALUE)
#error ALIAS_NAME and ALIAS_VALUE must identify the authored leaf
#endif

int ALIAS_NAME(void)
{
	return ALIAS_VALUE;
}
