extern volatile int mst_self_need;
volatile int mst_self_have = 41;

int bundle_entry(void)
{
	return mst_self_need + 1;
}
