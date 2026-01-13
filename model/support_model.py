import math
import torch
import torch.nn as nn
from torch.nn import init


class Input(nn.Module):
    def __init__(self):
        super(Input, self).__init__()

    def forward(self, x):
        return x


class ConvHole2D(nn.Conv2d):
    def __init__(
        self,
        in_channels,
        out_channels,
        kernel_size,
        stride=1,
        padding=0,
        padding_mode="zeros",
        dilation: int = 1,
        groups: int = 1,
        bias: bool = True,
        kernel_initializer=None,
        device=None,
        dtype=None,
    ):
        super(ConvHole2D, self).__init__(
            in_channels,
            out_channels,
            kernel_size,
            stride,
            padding,
            dilation,
            groups,
            bias,
            padding_mode,
            device,
            dtype,
        )
        assert self.groups == 1, "(groups > 1) is Not implemented!"

        # import pdb; pdb.set_trace()

        _w = torch.empty(
            out_channels,
            in_channels // groups,
            self.kernel_size[0] * self.kernel_size[1] - 1,
        )
        if kernel_initializer is None:
            init.kaiming_uniform_(_w, a=math.sqrt(5))
        else:
            nn.init.ones_(_w)

        self._oc, self._ic, self._p = _w.size()
        self._spot = nn.Parameter(torch.zeros([self._oc, self._ic, 1]), requires_grad=False)
        self.weight = nn.Parameter(_w, requires_grad=True)

    # overwrite default behavior
    def forward(self, input):
        _kernel = torch.cat(
            [self.weight[:, :, : self._p // 2],
            self._spot,
            self.weight[:, :, self._p // 2 :]],
            dim=2
        )
        _kernel = _kernel.view([self._oc, self._ic, *self.kernel_size])
        return self._conv_forward(input, _kernel, self.bias)



class ConvHole3D(nn.Conv3d):
    def __init__(
        self,
        in_channels,
        out_channels,
        kernel_size,
        stride=1,
        padding=0,
        padding_mode="zeros",
        dilation: int = 1,
        groups: int = 1,
        bias: bool = True,
        kernel_initializer=None,
        device=None,
        dtype=None,
    ):
        super(ConvHole3D, self).__init__(
            in_channels,
            out_channels,
            kernel_size,
            stride,
            padding,
            dilation,
            groups,
            bias,
            padding_mode,
            device,
            dtype,
        )
        assert self.groups == 1, "(groups > 1) is Not implemented!"

        _w = torch.empty(
            out_channels,
            in_channels // groups,
            self.kernel_size[0] * self.kernel_size[1] * self.kernel_size[2] - 1,
        )
        if kernel_initializer is None:
            init.kaiming_uniform_(_w, a=math.sqrt(5))
        else:
            nn.init.ones_(_w)


        self._oc, self._ic, self._p = _w.size()
        self._spot = nn.Parameter(torch.zeros([self._oc, self._ic, 1]), requires_grad=False)

        self.weight = nn.Parameter(_w, requires_grad=True)

    # overwrite default behavior
    def forward(self, input):
        _kernel = torch.cat(
            [self.weight[:, :, : self._p // 2],
            self._spot,
            self.weight[:, :, self._p // 2 :]],
            dim=2
        )
        _kernel = _kernel.view([self._oc, self._ic, *self.kernel_size])
        return self._conv_forward(input, _kernel, self.bias)

import torch
import torch.nn as nn

class SUPPORT(nn.Module):
    """
    Blindspot network

    Arguments:
        in_channels: the number of input channels (int)
        mid_channels: the number of middle channels ([int])
    """
    def __init__(self, in_channels, mid_channels=[16, 32, 64, 128, 256], depth=5,\
         blind_conv_channels=64, one_by_one_channels=[32, 16],\
            last_layer_channels=[64, 32, 16], bs_size=1, bp=False):
        super(SUPPORT, self).__init__()

        # check arguments
        if len(mid_channels) < 2:
            raise Exception("length of mid_channels must be larger than 1")
        # if depth % 2 == 0:
        #     raise Exception("depth must be an odd number")
        if type(blind_conv_channels) != int:
            raise Exception("type of blind_conv_channels must be an integer")
        if not all([type(i)==int for i in one_by_one_channels]):
            raise Exception("one_by_one_channels must be an integer array")

        self.in_channels = in_channels
        self.out_channels = 1
        self.mid_channels = mid_channels
        self.depth = depth
        self.depth3x3 = depth
        self.depth5x5 = depth - 2

        self.blind_conv_channels = blind_conv_channels
        self.one_by_one_channels = one_by_one_channels

        self.last_layer_channels = last_layer_channels

        if type(bs_size) == int:
            bs_size = [bs_size, bs_size]
        self.bs_size = bs_size

        self.bp = bp
        if in_channels == 1:
            self.twod = True
        else:
            self.twod = False

        assert not (self.bp and self.twod), "two options cannot be selected in same time."

        # initialize
        self.relu = nn.ReLU()
        self.leaky_relu = nn.LeakyReLU()
        self.maxpool_2d = nn.MaxPool2d(kernel_size=2, stride=2)
        self.upsample_2d = nn.Upsample(scale_factor=2)

        if self.twod is False:
            self._gen_unet()
        if bp is False:
            self._gen_bsnet()

        # last layer
        last_layers = []
        for idx, c in enumerate(last_layer_channels):
            if idx == 0:
                if bp is False and self.twod is False:
                    last_layers.append(nn.Conv2d(2*one_by_one_channels[-1], c, kernel_size=1, padding=0))
                else:
                    last_layers.append(nn.Conv2d(one_by_one_channels[-1], c, kernel_size=1, padding=0))
            else:
                last_layers.append(nn.Conv2d(last_layer_channels[idx-1], c, kernel_size=1, padding=0))
        last_layers.append(nn.Conv2d(c, self.out_channels, kernel_size=1, padding=0))

        self.last_layers = nn.ModuleList(last_layers)

    def _gen_unet(self):
        # (Unet) encoding layers
        self.enc_layers = []
        for i in range(len(self.mid_channels)):
            if i == 0:
                self.enc_layers.append(nn.Conv2d(self.in_channels-1, self.mid_channels[i], kernel_size=3, padding=1))
            else:
                self.enc_layers.append(nn.Conv2d(self.mid_channels[i-1], self.mid_channels[i], kernel_size=3, padding=1))
        self.enc_layers = nn.ModuleList(self.enc_layers)

        # (Unet) decoding layers
        self.dec_layers = []
        for i in range(len(self.mid_channels)-1):
            self.dec_layers.append(nn.Conv2d(self.mid_channels[i] + self.mid_channels[i+1], self.mid_channels[i], kernel_size=3, padding=1))
        self.dec_layers = nn.ModuleList(reversed(self.dec_layers))

        # (Unet) 1x1 convs
        self.unet_1_convs = []
        for idx, c in enumerate(self.one_by_one_channels):
            if idx == 0:
                self.unet_1_convs.append(nn.Conv2d(self.mid_channels[0], c, kernel_size=1, padding=0))
            else:
                self.unet_1_convs.append(nn.Conv2d(self.one_by_one_channels[idx-1], c, kernel_size=1, padding=0))
        self.unet_1_convs = nn.ModuleList(self.unet_1_convs)

    def _gen_bsnet(self):
        # (BS) additional parameters
        self.scalars_3x3 = []
        # c_in_first = self.one_by_one_channels[-1] + 1
        for d in range(self.depth3x3 - 1):
            c_in = 1 if d == 0 else self.blind_conv_channels
            self.scalars_3x3.append(nn.Parameter(torch.ones(c_in), requires_grad=True))
        self.scalars_3x3 = nn.ParameterList(self.scalars_3x3)

        self.scalars_5x5 = []
        for d in range(self.depth5x5 - 1):
            c_in = 1 if d == 0 else self.blind_conv_channels
            self.scalars_5x5.append(nn.Parameter(torch.ones(c_in), requires_grad=True))
        self.scalars_5x5 = nn.ParameterList(self.scalars_5x5)

        # (BS) first layer to process Unet output
        conv3x3 = []
        conv3x3.append(
            nn.Conv2d(
                self.one_by_one_channels[-1],
                self.blind_conv_channels,
                kernel_size=3,
                stride=1,
                padding=1,
                bias=True,
                padding_mode="zeros",
                dilation=1,
            )
        )
        conv3x3.append(self.relu)
        self.conv3x3 = nn.ModuleList(conv3x3)

        conv5x5 = []
        conv5x5.append(
            nn.Conv2d(
                self.one_by_one_channels[-1],
                self.blind_conv_channels,
                kernel_size=5,
                stride=1,
                padding=2,
                bias=True,
                padding_mode="zeros",
                dilation=1,
            )
        )
        conv5x5.append(self.relu)
        self.conv5x5 = nn.ModuleList(conv5x5)

        # (BS) dilated convolutions with blind-spot
        blind_conv3x3_layers = []
        for d in range(self.depth3x3):
            c_in = 1 if d == 0 else self.blind_conv_channels
            # """
            pd = [pow(2, d), pow(2, d)]
            if d == self.depth3x3 - 1:
                pd[0] = pd[0] + self.bs_size[0] // 2
                pd[1] = pd[1] + self.bs_size[1] // 2
            # """
            # pd = pow(2, d)*(self.bs_size//2+1)
            blind_conv3x3_layers.append(
                ConvHole2D(
                    c_in,
                    self.blind_conv_channels,
                    kernel_size=3,
                    stride=1,
                    padding=pd, # pow(2, d)*(self.bs_size//2+1),
                    bias=True,
                    padding_mode="zeros",
                    dilation=pd, # pow(2, d)*(self.bs_size//2+1),
                )
            )
            blind_conv3x3_layers.append(self.relu)
        self.blind_convs3x3 = nn.ModuleList(blind_conv3x3_layers)

        blind_conv5x5_layers = []
        for d in range(self.depth5x5):
            c_in = 1 if d == 0 else self.blind_conv_channels
            # """
            pd = [pow(3, d), pow(3, d)]
            if d == self.depth5x5 - 1: # assume we will use only last layer if the bs_size is larger than 1
                pd[0] = pd[0] + self.bs_size[0] // 2
                pd[1] = pd[1] + self.bs_size[1] // 2
            # """
            # pd = (pow(3, d)*(self.bs_size//2+1))
            blind_conv5x5_layers.append(
                ConvHole2D(
                    c_in,
                    self.blind_conv_channels,
                    kernel_size=5,
                    stride=1,
                    padding=[pd[0] * 2, pd[1] * 2], # pd * 2, # (pow(3, d)*(self.bs_size//2+1)) * 2,
                    bias=True,
                    padding_mode="zeros",
                    dilation=pd, # *(self.bs_size//2+1),
                )
            )
            blind_conv5x5_layers.append(self.relu)
        self.blind_convs5x5 = nn.ModuleList(blind_conv5x5_layers)

        # (BS) 1x1 convolutions
        out_convs =[]
        for idx, c in enumerate(self.one_by_one_channels):
            if self.bs_size[0] == 1 and self.bs_size[1] == 1:
                c_in = (
                    self.blind_conv_channels * (self.depth3x3 + self.depth5x5)
                    if idx == 0
                    else self.one_by_one_channels[idx - 1]
                )
            else:
                c_in = (
                    self.blind_conv_channels * 2
                    if idx == 0
                    else self.one_by_one_channels[idx - 1]
                )
            out_convs.append(
                nn.Conv2d(
                    c_in,
                    c,
                    kernel_size=1,
                    padding=0,
                    bias=True,
                )
            )
            out_convs.append(self.relu)
        self.out_convs = nn.ModuleList(out_convs)

    def forward_unet(self, x):
        # x = [b, T, d1, d2]
        # d1, d2 = 512, paper reference
        xs = []
        # print(x.size(), x.min(), x.max(), 'unet')

        for idx, enc_layer in enumerate(self.enc_layers):
            x = self.relu(enc_layer(x))
            if idx != len(self.enc_layers) - 1:
                xs.append(x)
                x = self.maxpool_2d(x)

        for idx, dec_layer in enumerate(self.dec_layers):
            # up_ = self.upsample_2d(x)
            # print(xs[-idx-1].size(), xs[-idx-1].size()[2:])
            up_ = torch.nn.functional.interpolate(x, xs[-idx-1].size()[2:])

            x = torch.cat([up_, xs[-idx-1]], dim=1)
            x = self.relu(dec_layer(x))

        for one_conv in self.unet_1_convs:
            x = self.relu(one_conv(x))

        return x

    def forward_bsnet(self, x, unet_out):
        # x : bsnet input
        # unet_out : unet output

        hc = []

        if unet_out is not None:
            unet_out1 = self.conv3x3[0](unet_out)
            unet_out1 = self.conv3x3[1](unet_out1)

        for c in range(self.depth3x3):
            if c == 0:
                x1 = x
            else:
                # x1 = x1 + x1.max() * inp
                # print(x.size())
                x1 = x1 + (self.scalars_3x3[c - 1] * x.permute(0, 2, 3, 1)).permute(0, 3, 1, 2)

            x1 = self.blind_convs3x3[2 * c](x1)
            x1 = self.blind_convs3x3[2 * c + 1](x1)

            if c == 0 and unet_out is not None:
                x1 = x1 + unet_out1

            if self.bs_size[0] == 1 and self.bs_size[1] == 1:
                hc.append(x1)
            else:
                if c == self.depth3x3 - 1:
                    hc.append(x1)

        if unet_out is not None:
            unet_out2 = self.conv5x5[0](unet_out)
            unet_out2 = self.conv5x5[1](unet_out2)

        for c in range(self.depth5x5):
            if c == 0:
                x2 = x
            else:
                x2 = x2 + (self.scalars_5x5[c - 1] * x.permute(0, 2, 3, 1)).permute(0, 3, 1, 2)

            x2 = self.blind_convs5x5[2 * c](x2)
            x2 = self.blind_convs5x5[2 * c + 1](x2)

            if c == 0 and unet_out is not None:
                x2 = x2 + unet_out2

            if self.bs_size[0] == 1 and self.bs_size[1] == 1:
                hc.append(x2)
            else:
                if c == self.depth5x5 - 1:
                    hc.append(x2)

        x = torch.cat(hc, dim=1)

        for o_m in self.out_convs:
            x = o_m(x)

        return x

    def forward(self, x):
        # x = [b, T, d1, d2]
        # d1, d2 = 512, paper reference

        unet_in = torch.cat([x[:, :self.in_channels//2, :, :], x[:, self.in_channels//2 + 1:, :, :]], dim=1)
        bsnet_in = torch.unsqueeze(x[:, self.in_channels//2, :, :], dim=1)

        if self.bp:
            unet_out = self.forward_unet(unet_in)
            x = unet_out
        elif self.twod:
            unet_out = None
            x = self.forward_bsnet(bsnet_in, unet_out)
        else:
            unet_out = self.forward_unet(unet_in)
            bsnet_out = self.forward_bsnet(bsnet_in, unet_out)

            x = torch.cat([unet_out, bsnet_out], dim=1)

        for idx, layer in enumerate(self.last_layers):
            if idx != len(self.last_layers)-1:
                x = self.relu(layer(x))
            else:
                x = layer(x)

        return x

import os
import math
import argparse
import numpy as np


def parse_arguments():
    parser = argparse.ArgumentParser()
    # experiment
    parser.add_argument("--random_seed", type=int, default=0, help="random seed for rng")
    parser.add_argument("--epoch", type=int, default=0, help="epoch to start training from (need epoch-1 model)")
    parser.add_argument("--n_epochs", type=int, default=500, help="number of epochs of training")
    parser.add_argument("--exp_name", type=str, default="myEXP", help="name of the experiment")
    parser.add_argument("--results_dir", type=str, default="./results", help="root directory to save results")
    parser.add_argument("--input_frames", type=int, default=61, help="# of input frames")
    # parser.add_argument("--cuda_device", type=int, default=[0], nargs="+", help="cuda devices to use")

    # dataset
    parser.add_argument("--is_folder", action="store_true", help="noisy_data is folder")
    parser.add_argument("--noisy_data", type=str, nargs="+", help="List of path to the noisy data")
    parser.add_argument("--patch_size", type=int, default=[61, 128, 128], nargs="+", help="size of the patches")
    parser.add_argument("--patch_interval", type=int, default=[1, 64, 64], nargs="+", help="size of the patch interval")
    parser.add_argument("--batch_size", type=int, default=16, help="size of the batches")

    # model
    parser.add_argument("--depth", type=int, default=5, help="the number of blind spot convolutions, must be an odd number")
    parser.add_argument("--blind_conv_channels", type=int, default=64, help="the number of channels of blind spot convolutions")
    parser.add_argument("--one_by_one_channels", type=int, default=[32, 16], nargs="+", help="the number of channels of 1x1 convolutions")
    parser.add_argument("--last_layer_channels", type=int, default=[64, 32, 16], nargs="+", help="the number of channels of 1x1 convs after UNet")
    parser.add_argument("--bs_size", type=int, default=[3, 3], nargs="+", help="the size of the blind spot")
    parser.add_argument("--bp", action="store_true", help="blind plane")
    parser.add_argument("--unet_channels", type=int, default=[16, 32, 64, 128, 256], nargs="+", help="the number of channels of UNet")

    # training
    parser.add_argument("--lr", type=float, default=5e-4, help="adam: learning rate")
    parser.add_argument("--loss_coef", type=float, default=[0.5, 0.5], nargs="+", help="L1/L2 loss coefficients")

    # util
    parser.add_argument("--use_CPU", action="store_true", help="use CPU")
    parser.add_argument("--n_cpu", type=int, default=8, help="number of cpu threads to use during batch generation")
    parser.add_argument("--logging_interval_batch", type=int, default=50, help="interval between logging info (in batches)")
    parser.add_argument("--logging_interval", type=int, default=1, help="interval between logging info (in epochs)")
    parser.add_argument("--sample_interval", type=int, default=10, help="interval between saving denoised samples")
    parser.add_argument("--sample_max_t", type=int, default=600, help="maximum time step of saving sample")
    parser.add_argument("--checkpoint_interval", type=int, default=1, help="interval between saving trained models (in epochs)")
    opt = parser.parse_args()

    # argument checking
    if (opt.input_frames) != opt.patch_size[0]:
        raise Exception("input frames must be equal to z-frames of patch_size")
    if len(opt.loss_coef) != 2:
        raise Exception("loss_coef must be length-2 array")

    if opt.is_folder:
        tmp_root = opt.noisy_data[0]
        tmp_files = os.listdir(tmp_root)
        opt.noisy_data = [os.path.join(tmp_root, i) for i in tmp_files]

    return opt


def get_coordinate(img_size, patch_size, patch_interval):
    """DeepCAD version of stitching
    https://github.com/cabooster/DeepCAD/blob/53a9b8491170e298aa7740a4656b4f679ded6f41/DeepCAD_pytorch/data_process.py#L374
    """
    whole_s, whole_h, whole_w = img_size
    img_s, img_h, img_w = patch_size
    gap_s, gap_h, gap_w = patch_interval

    cut_w = (img_w - gap_w)/2
    cut_h = (img_h - gap_h)/2
    cut_s = (img_s - gap_s)/2

    # print(whole_s, whole_h, whole_w)
    # print(img_s, img_h, img_w)
    # print(gap_s, gap_h, gap_w)

    num_w = math.ceil((whole_w-img_w+gap_w)/gap_w)
    num_h = math.ceil((whole_h-img_h+gap_h)/gap_h)
    num_s = math.ceil((whole_s-img_s+gap_s)/gap_s)

    coordinate_list = []
    for x in range(0,num_h):
        for y in range(0,num_w):
            for z in range(0,num_s):
                single_coordinate={'init_h':0, 'end_h':0, 'init_w':0, 'end_w':0, 'init_s':0, 'end_s':0}
                if x != (num_h-1):
                    init_h = gap_h*x
                    end_h = gap_h*x + img_h
                elif x == (num_h-1):
                    init_h = whole_h - img_h
                    end_h = whole_h

                if y != (num_w-1):
                    init_w = gap_w*y
                    end_w = gap_w*y + img_w
                elif y == (num_w-1):
                    init_w = whole_w - img_w
                    end_w = whole_w

                if z != (num_s-1):
                    init_s = gap_s*z
                    end_s = gap_s*z + img_s
                elif z == (num_s-1):
                    init_s = whole_s - img_s
                    end_s = whole_s
                single_coordinate['init_h'] = init_h
                single_coordinate['end_h'] = end_h
                single_coordinate['init_w'] = init_w
                single_coordinate['end_w'] = end_w
                single_coordinate['init_s'] = init_s
                single_coordinate['end_s'] = end_s

                if y == 0:
                    if num_w > 1:
                        single_coordinate['stack_start_w'] = y*gap_w
                        single_coordinate['stack_end_w'] = y*gap_w+img_w-cut_w
                        single_coordinate['patch_start_w'] = 0
                        single_coordinate['patch_end_w'] = img_w-cut_w
                    else:
                        single_coordinate['stack_start_w'] = 0
                        single_coordinate['stack_end_w'] = img_w
                        single_coordinate['patch_start_w'] = 0
                        single_coordinate['patch_end_w'] = img_w
                elif y == num_w-1:
                    single_coordinate['stack_start_w'] = whole_w-img_w+cut_w
                    single_coordinate['stack_end_w'] = whole_w
                    single_coordinate['patch_start_w'] = cut_w
                    single_coordinate['patch_end_w'] = img_w
                else:
                    single_coordinate['stack_start_w'] = y*gap_w+cut_w
                    single_coordinate['stack_end_w'] = y*gap_w+img_w-cut_w
                    single_coordinate['patch_start_w'] = cut_w
                    single_coordinate['patch_end_w'] = img_w-cut_w

                if x == 0:
                    if num_h > 1:
                        single_coordinate['stack_start_h'] = x*gap_h
                        single_coordinate['stack_end_h'] = x*gap_h+img_h-cut_h
                        single_coordinate['patch_start_h'] = 0
                        single_coordinate['patch_end_h'] = img_h-cut_h
                    else:
                        single_coordinate['stack_start_h'] = 0
                        single_coordinate['stack_end_h'] = x*gap_h+img_h
                        single_coordinate['patch_start_h'] = 0
                        single_coordinate['patch_end_h'] = img_h
                elif x == num_h-1:
                    single_coordinate['stack_start_h'] = whole_h-img_h+cut_h
                    single_coordinate['stack_end_h'] = whole_h
                    single_coordinate['patch_start_h'] = cut_h
                    single_coordinate['patch_end_h'] = img_h
                else:
                    single_coordinate['stack_start_h'] = x*gap_h+cut_h
                    single_coordinate['stack_end_h'] = x*gap_h+img_h-cut_h
                    single_coordinate['patch_start_h'] = cut_h
                    single_coordinate['patch_end_h'] = img_h-cut_h

                if z == 0:
                    if num_s > 1:
                        single_coordinate['stack_start_s'] = z*gap_s
                        single_coordinate['stack_end_s'] = z*gap_s+img_s-cut_s
                        single_coordinate['patch_start_s'] = 0
                        single_coordinate['patch_end_s'] = img_s-cut_s
                    else:
                        single_coordinate['stack_start_s'] = z*gap_s
                        single_coordinate['stack_end_s'] = z*gap_s+img_s
                        single_coordinate['patch_start_s'] = 0
                        single_coordinate['patch_end_s'] = img_s
                elif z == num_s-1:
                    single_coordinate['stack_start_s'] = whole_s-img_s+cut_s
                    single_coordinate['stack_end_s'] = whole_s
                    single_coordinate['patch_start_s'] = cut_s
                    single_coordinate['patch_end_s'] = img_s
                else:
                    single_coordinate['stack_start_s'] = z*gap_s+cut_s
                    single_coordinate['stack_end_s'] = z*gap_s+img_s-cut_s
                    single_coordinate['patch_start_s'] = cut_s
                    single_coordinate['patch_end_s'] = img_s-cut_s

                coordinate_list.append(single_coordinate)

    return coordinate_list

import skimage.io as skio
import numpy as np
import torch
from torch.utils.data import Dataset, DataLoader

def random_transform(input, target, rng, is_rotate=True):
    """
    Randomly rotate/flip the image

    Arguments:
        input: input image stack (Pytorch Tensor with dimension [b, T, X, Y])
        target: targer image stack (Pytorch Tensor with dimension [b, T, X, Y]), can be None
        rng: numpy random number generator

    Returns:
        input: randomly rotated/flipped input image stack (Pytorch Tensor with dimension [b, T, X, Y])
        target: randomly rotated/flipped target image stack (Pytorch Tensor with dimension [b, T, X, Y])
    """
    rand_num = rng.integers(0, 4) # random number for rotation
    rand_num_2 = rng.integers(0, 2) # random number for flip

    if is_rotate:
        if rand_num == 1:
            input = torch.rot90(input, k=1, dims=(2, 3))
            if target is not None:
                target = torch.rot90(target, k=1, dims=(2, 3))
        elif rand_num == 2:
            input = torch.rot90(input, k=2, dims=(2, 3))
            if target is not None:
                target = torch.rot90(target, k=2, dims=(2, 3))
        elif rand_num == 3:
            input = torch.rot90(input, k=3, dims=(2, 3))
            if target is not None:
                target = torch.rot90(target, k=3, dims=(2, 3))

    if rand_num_2 == 1:
        input = torch.flip(input, dims=[2])
        if target is not None:
            target = torch.flip(target, dims=[2])

    return input, target


def normalize(image):
    """
    Normalize the image to [mean/std]=[0/1]

    Arguments:
        image: image stack (Pytorch Tensor with dimension [T, X, Y])

    Returns:
        image: normalized image stack (Pytorch Tensor with dimension [T, X, Y])
        mean_image: mean of the image stack (np.float)
        std_image: standard deviation of the image stack (np.float)
    """
    mean_image = torch.mean(image)
    std_image = torch.std(image)

    image -= mean_image
    image /= std_image

    return image, mean_image, std_image


class DatasetSUPPORT(Dataset):
    def __init__(self, noisy_images, patch_size=[61, 128, 128], patch_interval=[10, 64, 64], load_to_memory=True,\
        transform=None, random_patch=True, random_patch_seed=0):
        """
        Arguments:
            noisy_images: list of noisy image stack ([Tensor with dimension [t, x, y]])
            patch_size: size of the patch ([int]), ([t, x, y])
            patch_interval: interval between each patch ([int]), ([t, x, y])
            load_to_memory: whether load data into memory or not (bool)
            transform: function of transformation (function)
            random_patch: sample patch in random or not (bool)
            random_patch_seed: seed for randomness (int)
            algorithm: the algorithm of use (str)
        """
        # check arguments
        if len(patch_size) != 3:
            raise Exception("length of patch_size must be 3")
        if len(patch_interval) != 3:
            raise Exception("length of patch_interval must be 3")

        # initialize
        self.data_weight = []
        for noisy_image in noisy_images:
            self.data_weight.append(torch.numel(noisy_image))

        self.patch_size = patch_size
        self.patch_interval = patch_interval
        self.transform = transform
        self.random_patch = random_patch
        self.patch_rng = np.random.default_rng(random_patch_seed)

        self.noisy_images = noisy_images
        self.mean_images = []
        self.std_images = []
        for idx, noisy_image in enumerate(noisy_images):
            noisy_image, mean_image, std_image = normalize(noisy_image)
            self.noisy_images[idx] = noisy_image
            self.mean_images.append(mean_image)
            self.std_images.append(std_image)
        self.mean_images = torch.tensor(self.mean_images)
        self.std_images = torch.tensor(self.std_images)

        # generate index
        self.indices_ds = []
        for noisy_image in self.noisy_images:
            indices = []
            tmp_size = noisy_image.size()
            if np.any(tmp_size < np.array(self.patch_size)):
                raise Exception("patch size is larger than data size")

            for k in range(3):
                z_range = list(range(0, tmp_size[k]-self.patch_size[k]+1, self.patch_interval[k]))
                if tmp_size[k] - self.patch_size[k] > z_range[-1]:
                    z_range.append(tmp_size[k]-self.patch_size[k])
                indices.append(z_range)
            self.indices_ds.append(indices)


    def __len__(self):
        total = 0
        for indices in self.indices_ds:
            total += len(indices[0]) * len(indices[1]) * len(indices[2])

        return total

    def __getitem__(self, i):
        # slicing
        if self.random_patch:
            ds_idx = self.patch_rng.choice(len(self.data_weight), 1)[0]
            t_idx = self.patch_rng.integers(0, self.noisy_images[ds_idx].size()[0]-self.patch_size[0]+1)
            y_idx = self.patch_rng.integers(0, self.noisy_images[ds_idx].size()[1]-self.patch_size[1]+1)
            z_idx = self.patch_rng.integers(0, self.noisy_images[ds_idx].size()[2]-self.patch_size[2]+1)
        else:
            ds_idx = 0
            t_idx = self.indices_ds[ds_idx][0][i // (len(self.indices_ds[ds_idx][1]) * len(self.indices_ds[ds_idx][2]))]
            y_idx = self.indices_ds[ds_idx][1][(i % (len(self.indices_ds[ds_idx][1]) * len(self.indices_ds[ds_idx][2]))) // len(self.indices_ds[ds_idx][2])]
            z_idx = self.indices_ds[ds_idx][2][i % len(self.indices_ds[ds_idx][2])]

        # input dataset range
        t_range = slice(t_idx, t_idx + self.patch_size[0])
        y_range = slice(y_idx, y_idx + self.patch_size[1])
        z_range = slice(z_idx, z_idx + self.patch_size[2])

        noisy_image = self.noisy_images[ds_idx][t_range, y_range, z_range]

        return noisy_image, torch.tensor([[t_idx, t_idx + self.patch_size[0]],\
            [y_idx, y_idx + self.patch_size[1]], [z_idx, z_idx + self.patch_size[2]]]), torch.tensor(ds_idx)


class DatasetSUPPORT_test_stitch(Dataset):
    def __init__(self, noisy_image, patch_size=[61, 128, 128], patch_interval=[10, 64, 64], load_to_memory=True,\
        transform=None, random_patch=False, random_patch_seed=0):
        """
        Arguments:
            noisy_image: noisy image stack (Tensor with dimension [t, x, y])
            patch_size: size of the patch ([int]), ([t, x, y])
            patch_interval: interval between each patch ([int]), ([t, x, y])
            load_to_memory: whether load data into memory or not (bool)
            transform: function of transformation (function)
            random_patch: sample patch in random or not (bool)
            random_patch_seed: seed for randomness (int)
        """
        # check arguments
        if len(patch_size) != 3:
            raise Exception("length of patch_size must be 3")
        if len(patch_interval) != 3:
            raise Exception("length of patch_interval must be 3")

        self.patch_size = patch_size
        self.patch_interval = patch_interval
        self.transform = transform
        self.random_patch = random_patch
        self.patch_rng = np.random.default_rng(random_patch_seed)
        self.noisy_image = noisy_image
        # Remove global normalization here!

        # generate index
        self.indices = []
        tmp_size = self.noisy_image.size()
        if np.any(tmp_size < np.array(self.patch_size)):
            raise Exception("patch size is larger than data size")

        self.indices = get_coordinate(tmp_size, patch_size, patch_interval)

    def __len__(self):
        return len(self.indices) # len(self.indices[0]) * len(self.indices[1]) * len(self.indices[2])

    def __getitem__(self, i):
        # slicing
        if self.random_patch:
            idx = self.patch_rng.integers(0, len(self.indices) - 1)
        else:
            idx = i
        single_coordinate = self.indices[idx]

        # input dataset range
        init_h = single_coordinate['init_h']
        end_h = single_coordinate['end_h']
        init_w = single_coordinate['init_w']
        end_w = single_coordinate['end_w']
        init_s = single_coordinate['init_s']
        end_s = single_coordinate['end_s']

        # for stitching dataset range
        noisy_image = self.noisy_image[init_s:end_s,init_h:end_h,init_w:end_w]

        # Compute mean/std for this window
        mean = torch.mean(noisy_image)
        std = torch.std(noisy_image)
        if std == 0:
            std = 1.0
        noisy_image_norm = (noisy_image - mean) / std

        if self.transform:
            rand_i = self.patch_rng.integers(0, self.transform.n_masks)
            rand_t = self.patch_rng.integers(0, 2)
            noisy_image_norm = self.transform.mask(noisy_image_norm, rand_i, rand_t)

        return noisy_image_norm, mean, std, single_coordinate


def gen_train_dataloader(patch_size, patch_interval, batch_size, noisy_data_list):
    """
    Generate dataloader for training

    Arguments:
        patch_size: opt.patch_size
        patch_interval: opt.patch_interval
        noisy_data_list: opt.noisy_data

    Returns:
        dataloader_train
    """
    noisy_images_train = []

    for noisy_data in noisy_data_list:
        noisy_image = torch.from_numpy(skio.imread(noisy_data).astype(np.float32)).type(torch.FloatTensor)
        print(f"Loaded {noisy_data} Shape : {noisy_image.shape}")
        if len(noisy_image.shape) == 2:
            noisy_image = noisy_image.unsqueeze(0)
        T, _, _ = noisy_image.shape
        noisy_images_train.append(noisy_image)

    dataset_train = DatasetSUPPORT(noisy_images_train, patch_size=patch_size,\
        patch_interval=patch_interval, transform=None, random_patch=True)
    dataloader_train = DataLoader(dataset_train, batch_size=batch_size, shuffle=True)

    return dataloader_train

import numpy as np
import torch
import skimage.io as skio
from tqdm import tqdm

def validate(test_dataloader, model):
    """
    Validate a model with a test data, using per-patch normalization/denormalization (like the GUI).
    Arguments:
        test_dataloader: (Pytorch DataLoader)
        model: (Pytorch nn.Module)
    Returns:
        denoised_stack: denoised image stack (Numpy array with dimension [T, X, Y])
    """

    with torch.no_grad():
        model.eval()
        # Get dimensions
        noisy_image = test_dataloader.dataset.noisy_image
        t, h, w = noisy_image.shape
        pad_size = 30  # GUI uses 30 frames padding
        padded_image = torch.zeros(t + 2*pad_size, h, w)
        padded_image[pad_size:-pad_size] = noisy_image
        padded_image[:pad_size] = noisy_image[0].unsqueeze(0).repeat(pad_size, 1, 1)
        padded_image[-pad_size:] = noisy_image[-1].unsqueeze(0).repeat(pad_size, 1, 1)
        # Create new dataset with padded volume
        testset = DatasetSUPPORT_test_stitch(padded_image, patch_size=test_dataloader.dataset.patch_size,
                                           patch_interval=test_dataloader.dataset.patch_interval)
        testloader = torch.utils.data.DataLoader(testset, batch_size=test_dataloader.batch_size)
        denoised_stack = np.zeros((t, h, w), dtype=np.float32)
        for _, (noisy_image_norm, mean, std, single_coordinate) in enumerate(tqdm(testloader, desc="validate")):
            noisy_image_norm = noisy_image_norm.cuda() #[b, z, y, x]
            noisy_image_denoised = model(noisy_image_norm)
            # Denormalize using per-patch mean/std
            mean = mean.view(-1, 1, 1, 1)
            std = std.view(-1, 1, 1, 1)
            noisy_image_denoised = noisy_image_denoised.cpu() * std + mean
            T = noisy_image_norm.size(1)
            for bi in range(noisy_image_norm.size(0)):
                stack_start_w = int(single_coordinate['stack_start_w'][bi])
                stack_end_w = int(single_coordinate['stack_end_w'][bi])
                patch_start_w = int(single_coordinate['patch_start_w'][bi])
                patch_end_w = int(single_coordinate['patch_end_w'][bi])
                stack_start_h = int(single_coordinate['stack_start_h'][bi])
                stack_end_h = int(single_coordinate['stack_end_h'][bi])
                patch_start_h = int(single_coordinate['patch_start_h'][bi])
                patch_end_h = int(single_coordinate['patch_end_h'][bi])
                stack_start_s = int(single_coordinate['init_s'][bi])
                actual_s = stack_start_s + (T//2)
                if actual_s >= pad_size and actual_s < (t + pad_size):
                    out_s = actual_s - pad_size
                    denoised_stack[out_s, stack_start_h:stack_end_h, stack_start_w:stack_end_w] \
                        = noisy_image_denoised[bi].squeeze()[patch_start_h:patch_end_h, patch_start_w:patch_end_w].cpu()
        return denoised_stack