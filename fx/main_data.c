/* Imports data missing from libmst.dylib, so binding fails at launch. */
extern int d_miss;

int main(void)
{
	return d_miss;
}
