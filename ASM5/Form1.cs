using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace ASM5
{
    public partial class Form1 : Form
    {
        Bitmap InputBitmap;
        public Form1()
        {
            InitializeComponent();
        }

        private void groupBox2_Enter(object sender, EventArgs e)
        {

        }

        private void pictureBox1_Click(object sender, EventArgs e)
        {

        }

        private void label4_Click(object sender, EventArgs e)
        {

        }

        private void label5_Click(object sender, EventArgs e)
        {

        }

        private void tableLayoutPanel2_Paint(object sender, PaintEventArgs e)
        {

        }

        private void label3_Click(object sender, EventArgs e)
        {

        }

        private void radioButton1_CheckedChanged(object sender, EventArgs e)
        {

        }

        private void radioButton3_CheckedChanged(object sender, EventArgs e)
        {

        }

        private void radioButton3_CheckedChanged_1(object sender, EventArgs e)
        {

        }

        private void label7_Click(object sender, EventArgs e)
        {

        }

        private void button1_Click(object sender, EventArgs e)
        {
            OpenFileDialog ofd = new OpenFileDialog();
            ofd.Filter = "Image Files|*.jpg;*.png;*.bmp;";

            if (ofd.ShowDialog() == DialogResult.OK)
            {
                InputBitmap = new Bitmap(ofd.FileName);
                pictureInput.Image = InputBitmap;
                LabelFile.Text = ofd.FileName;
            }

        }

        private void InputKernel_ValueChanged(object sender, EventArgs e)
        {
            var nud = (NumericUpDown)sender;

            int value = (int)nud.Value;

            if (value % 2 == 0)
            {
                nud.Value = value + 1;
            }
        }
        float gaussian_distribution(int x, float sigma)
        {
            return (float)Math.Exp(-(x * x) / (2 * sigma * sigma));
        }
        [DllImport(@"C:\Users\mkowa\source\repos\ASM5\x64\Debug\gauss_cpp.dll")]
        static extern void gauss(IntPtr data, int depth, int height, int width, int stride, int kernel_size, float sigma);
        private void buttonCpp_Click(object sender, EventArgs e)
        {
            if (InputBitmap == null)
            {
                MessageBox.Show("Please load an image first.");
                return;
            }

            Rectangle rect = new Rectangle(0, 0, InputBitmap.Width, InputBitmap.Height);

            Bitmap output = InputBitmap.Clone(rect, PixelFormat.Format32bppArgb);

            BitmapData data = output.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
            // run 
            progressBar.Value = 0;
            //pass: pointer to data, bit depth, height, stride, eventually where each threads data stops
            gauss(data.Scan0, 4, output.Height,output.Width, data.Stride, ((int)InputKernel.Value), ((float)InputSigma.Value));
           
            progressBar.Maximum = 101;
            progressBar.Value=(101);
            progressBar.Value = (100);
            progressBar.Maximum = 100; 

            output.UnlockBits(data);
            pictureOutput.Image = output;
        }

        private void label6_Click(object sender, EventArgs e)
        {

        }
    }
}
